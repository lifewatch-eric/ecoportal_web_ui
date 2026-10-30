#!/usr/bin/env python3
"""Build a validated public projection without exposing the private staging copy."""
import configparser
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import urllib.error

METADATA = 'http://data.bioontology.org/metadata/'
ONTOLOGY = METADATA + 'Ontology'
SUBMISSION = METADATA + 'OntologySubmission'
AUXILIARY = {METADATA + name for name in ('Affiliation', 'Base', 'Category', 'Contact', 'Creator', 'CreatorIdentifier', 'Details', 'Metrics', 'OntologyFormat', 'OntologyType', 'SubmissionStatus', 'Title')}
AUXILIARY |= {'http://www.w3.org/ns/adms#Identifier', 'http://xmlns.com/foaf/0.1/Agent'}
SENSITIVE = {METADATA + name for name in ('User', 'IdentifierRequest', 'Note', 'Project', 'Reply', 'Review', 'Subscription', 'Role', 'NotificationType')}
INFRASTRUCTURE = {'http://localhost:8890/DAV/', 'http://www.openlinksw.com/schemas/virtrdf#', 'http://www.w3.org/2002/07/owl#', 'http://www.w3.org/ns/ldp#', 'urn:activitystreams-owl:map', 'urn:core:services:sparql'}
DATA = pathlib.Path('/srv/ontoportal/data')
SOURCE_CONFIG = pathlib.Path('/opt/virtuoso/database/virtuoso.ini')
PUBLIC_CONFIG = pathlib.Path('/opt/virtuoso-public/database/virtuoso.ini')
SOURCE = DATA / 'virtuoso/virtuoso.db'
PUBLIC = DATA / 'virtuoso-public'
HTTP, SQL = 18891, 18892


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def progress(phase):
    print(json.dumps({'phase': phase, 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}), flush=True)


def iri(value):
    if not re.match(r'^(https?://|urn:)', value) or re.search(r'[\s<>"{}|^`\\]', value):
        raise ValueError('Unsafe graph IRI')
    return '<' + value + '>'


def public_policy(metadata):
    ontology = metadata[ONTOLOGY]
    all_subjects = {r['s']['value'] for r in ontology}
    restricted = {r['s']['value'] for r in ontology if r['p']['value'].endswith('viewingRestriction') and r['o']['value'].lower() != 'public'}
    public = all_subjects - restricted
    submissions = {r['s']['value'] for r in metadata[SUBMISSION] if content_allowed(r['s']['value'], public)}
    selected = {ONTOLOGY: public, SUBMISSION: submissions}
    reachable = public | submissions
    seed = [r for graph in (ONTOLOGY, SUBMISSION) for r in metadata[graph] if r['s']['value'] in selected[graph]]
    reachable |= {r['o']['value'] for r in seed if r['o']['type'] == 'uri'}
    while True:
        expanded = reachable | {r['o']['value'] for graph in AUXILIARY for r in metadata.get(graph, []) if r['s']['value'] in reachable and r['o']['type'] == 'uri'}
        if expanded == reachable:
            break
        reachable = expanded
    selected.update({g: {r['s']['value'] for r in rows if r['s']['value'] in reachable} for g, rows in metadata.items() if g in AUXILIARY})
    return selected, public


def content_allowed(graph, public):
    return any(graph.startswith(subject + '/submissions/') for subject in public)


def sql(port, text):
    result = subprocess.run(['/opt/virtuoso/bin/isql', 'localhost:' + str(port), 'VERBOSE=OFF', 'PROMPT=OFF', 'ECHO=OFF'], input=text + '\nexit;\n', text=True, capture_output=True, timeout=300)
    require(result.returncode == 0 and '*** Error' not in result.stdout + result.stderr, 'Virtuoso SQL operation failed on port ' + str(port))


def query(port, text, timeout=150):
    data = urllib.parse.urlencode({'query': text, 'format': 'application/sparql-results+json', 'timeout': 120000}).encode()
    request = urllib.request.Request('http://127.0.0.1:' + str(port) + '/sparql', data=data)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        require(response.headers.get('X-SQL-State', '00000') == '00000', 'SPARQL returned partial results')
        return json.load(response)['results']['bindings']


def graphs(port):
    found = {r['g']['value'] for r in query(port, 'SELECT DISTINCT ?g WHERE { GRAPH ?g { ?s ?p ?o } }')}
    expected = int(query(port, 'SELECT (COUNT(DISTINCT ?g) AS ?n) WHERE { GRAPH ?g { ?s ?p ?o } }')[0]['n']['value'])
    require(len(found) == expected, 'SPARQL graph inventory is incomplete')
    return found


def rows(port, graph):
    found = query(port, 'SELECT ?s ?p ?o WHERE { GRAPH ' + iri(graph) + ' { ?s ?p ?o } }')
    require(len(found) == count(port, graph), 'SPARQL metadata result is incomplete')
    return found


def count(port, graph):
    return int(query(port, 'SELECT (COUNT(*) AS ?n) WHERE { GRAPH ' + iri(graph) + ' { ?s ?p ?o } }')[0]['n']['value'])


def read_metadata(port):
    existing = graphs(port)
    require({ONTOLOGY, SUBMISSION} <= existing, 'Missing ontology metadata')
    return {g: rows(port, g) for g in ({ONTOLOGY, SUBMISSION} | AUXILIARY) & existing}


def source_pid():
    value = subprocess.check_output(['systemctl', 'show', 'virtuoso', '-p', 'MainPID', '--value'], text=True).strip()
    require(value.isdigit() and int(value) > 0, 'Private Virtuoso is not running')
    return value


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            result.update(block)
    return result.hexdigest()


def signature(path):
    stat = path.stat()
    return stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns


def copy_snapshot(source, destination, interval):
    initial_pid = source_pid()
    try:
        # Vendor manual-copy method; reject any explicit checkpoint or restart during the copy.
        sql(1111, 'checkpoint_interval (-1);\ncheckpoint;')
        before = signature(source)
        shutil.copyfile(source, destination)
        require(source_pid() == initial_pid and signature(source) == before, 'Private database changed during copy')
        require(digest(destination) == digest(source) and source_pid() == initial_pid and signature(source) == before, 'Native copy differs or source changed')
    finally:
        sql(1111, 'checkpoint_interval (' + str(interval) + ');')


def config(path):
    result = configparser.ConfigParser(strict=False)
    result.optionxform = str
    require(result.read(path), 'Missing Virtuoso configuration')
    return result


def stage_configuration(folder, owner):
    cfg = config(SOURCE_CONFIG)
    for section in ('Database', 'TempDatabase'):
        for key in ('DatabaseFile', 'TransactionFile', 'ErrorLogFile', 'LockFile', 'xa_persistent_file'):
            if key in cfg[section]:
                cfg[section][key] = str(folder / 'db' / pathlib.Path(cfg[section][key]).name)
    cfg['Parameters']['ServerPort'] = '127.0.0.1:' + str(SQL)
    cfg['Parameters']['DisableUnixSocket'] = '1'
    cfg['Parameters']['SchedulerInterval'] = '0'
    cfg['Parameters']['CheckpointInterval'] = '60'
    cfg['HTTPServer']['ServerPort'] = '127.0.0.1:' + str(HTTP)
    cfg['HTTPServer']['ServerRoot'] = '/opt/virtuoso/vsp'
    for section, key in [('Parameters', 'SSLServerPort'), ('HTTPServer', 'SSLPort')]:
        cfg.remove_option(section, key)
    cfg.remove_section('Replication')
    cfg.remove_section('Zero Config')
    path = folder / 'stage.ini'
    with path.open('x') as stream:
        cfg.write(stream)
    os.chmod(path, 0o600)
    os.chown(path, owner.pw_uid, owner.pw_gid)
    return path


def start_stage(folder, cfg, owner):
    def user():
        os.setgroups([owner.pw_gid])
        os.setgid(owner.pw_gid)
        os.setuid(owner.pw_uid)
    with (folder / 'engine.log').open('ab') as log:
        child = subprocess.Popen(['/opt/virtuoso/bin/virtuoso-t', '+configfile', str(cfg), '+foreground'], cwd=folder / 'db', stdout=log, stderr=log, stdin=subprocess.DEVNULL, preexec_fn=user)
    try:
        for _ in range(60):
            require(child.poll() is None, 'Staging engine stopped; inspect protected engine log')
            output = subprocess.check_output(['ss', '-H', '-ltnp'], text=True)
            listeners = [line.split()[3] for line in output.splitlines() if 'pid=' + str(child.pid) + ',' in line]
            if listeners:
                require(set(listeners) <= {'127.0.0.1:' + str(HTTP), '127.0.0.1:' + str(SQL)}, 'Staging listener is not loopback-only')
            if len(listeners) == 2:
                query(HTTP, 'SELECT (1 AS ?ready) WHERE {}')
                return child
            time.sleep(1)
        raise RuntimeError('Staging engine did not become ready')
    except BaseException:
        stop_stage(child)
        raise


def stop_stage(child):
    if child and child.poll() is None:
        child.terminate()
        child.wait(timeout=90)
        require(child.returncode == 0, 'Staging engine did not exit cleanly')


def statement_set(bindings):
    return {json.dumps(row, sort_keys=True) for row in bindings}


def filter_stage(metadata, selected, public):
    existing = graphs(HTTP)
    keep = set(selected) | INFRASTRUCTURE | {g for g in existing if content_allowed(g, public)}
    content_counts = {g: count(HTTP, g) for g in existing if g in keep and g not in selected}
    for graph in sorted(existing - keep):
        sql(SQL, 'SPARQL CLEAR GRAPH ' + iri(graph) + ';')
    for graph, subjects in selected.items():
        remove = sorted({r['s']['value'] for r in metadata[graph]} - subjects)
        for offset in range(0, len(remove), 100):
            terms = ','.join(json.dumps(s) for s in remove[offset:offset + 100])
            sql(SQL, 'SPARQL DELETE { GRAPH ' + iri(graph) + ' { ?s ?p ?o } } WHERE { GRAPH ' + iri(graph) + ' { ?s ?p ?o FILTER (STR(?s) IN (' + terms + ')) } };')
    require(graphs(HTTP) <= keep, 'Unapproved graph remained in staging')
    for graph, subjects in selected.items():
        expected = [r for r in metadata[graph] if r['s']['value'] in subjects]
        require(statement_set(rows(HTTP, graph)) == statement_set(expected), 'Public metadata statement mismatch')
    for graph, expected in content_counts.items():
        require(count(HTTP, graph) == expected, 'Retained graph count changed')
    require(all(count(HTTP, g) == 0 for g in SENSITIVE), 'Sensitive graph remained in staging')
    sql(SQL, 'checkpoint;')
    return content_counts


def current_public_subjects():
    metadata = {ONTOLOGY: rows(8890, ONTOLOGY), SUBMISSION: []}
    return public_policy(metadata)[1]


def wait_public():
    deadline = time.monotonic() + 60
    while True:
        try:
            query(8891, 'SELECT (1 AS ?ready) WHERE {}', timeout=3)
            return
        except (urllib.error.URLError, TimeoutError, OSError):
            if time.monotonic() >= deadline:
                raise RuntimeError('Public SPARQL endpoint did not become ready')
            time.sleep(1)


def refresh(interval):
    import fcntl
    import pwd
    started = datetime.datetime.now(datetime.timezone.utc)
    backups = DATA / 'public-refresh-backups'
    backups.mkdir(mode=0o700, exist_ok=True)
    require(backups.resolve() == backups and backups.stat().st_uid == 0 and backups.stat().st_mode & 0o077 == 0, 'Unsafe backup directory')
    with (backups / 'job.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        owner_name = subprocess.check_output(['systemctl', 'show', 'virtuoso-public', '-p', 'User', '--value'], text=True).strip()
        owner = pwd.getpwnam(owner_name)
        require(shutil.disk_usage(DATA).free > SOURCE.stat().st_size * 3 + 536870912, 'Insufficient refresh/rollback disk space')
        old_public = {r['s']['value'] for r in rows(8891, ONTOLOGY)}
        old_safe = all(count(8891, g) == 0 for g in SENSITIVE)
        folder = pathlib.Path(tempfile.mkdtemp(prefix='public-refresh-stage-', dir=DATA))
        os.chown(folder, owner.pw_uid, owner.pw_gid)
        (folder / 'db').mkdir(mode=0o700)
        os.chown(folder / 'db', owner.pw_uid, owner.pw_gid)
        cfg = stage_configuration(folder, owner)
        child = None
        backup = backups / started.strftime('%Y%m%dT%H%M%S%fZ')
        moved = False
        public_stopped = False
        try:
            # Prove the exact configuration binds only loopback with an empty database first.
            child = start_stage(folder, cfg, owner)
            stop_stage(child)
            child = None
            progress('loopback-isolation-proven')
            for path in (folder / 'db').iterdir():
                require(path.is_file() and not path.is_symlink(), 'Unexpected staging file')
                path.unlink()
            copy_snapshot(SOURCE, folder / 'db/virtuoso.db', interval)
            progress('consistent-native-snapshot-created')
            os.chown(folder / 'db/virtuoso.db', owner.pw_uid, owner.pw_gid)
            child = start_stage(folder, cfg, owner)
            metadata = read_metadata(HTTP)
            selected, public = public_policy(metadata)
            require(public, 'Refuse empty public projection')
            content_counts = filter_stage(metadata, selected, public)
            progress('public-projection-filtered-and-verified')
            require(public <= current_public_subjects(), 'Visibility changed during refresh; retry from a fresh snapshot')
            stop_stage(child)
            child = None
            require(public <= current_public_subjects(), 'Visibility changed before promotion')
            progress('publishing-validated-public-projection')
            subprocess.run(['systemctl', 'stop', 'virtuoso-public'], check=True, timeout=90)
            public_stopped = True
            exchange_directories(PUBLIC, folder / 'db')
            moved = True
            os.rename(folder / 'db', backup)
            subprocess.run(['systemctl', 'start', 'virtuoso-public'], check=True, timeout=90)
            wait_public()
            require({r['s']['value'] for r in rows(8891, ONTOLOGY)} == public, 'Published ontology subjects differ')
            require(all(count(8891, g) == 0 for g in SENSITIVE), 'Published sensitive graph is nonempty')
            require(public <= current_public_subjects(), 'Visibility changed during publication')
            result = {'completed': True, 'started_utc': started.isoformat(), 'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'public_ontologies': len(public), 'retained_content_graphs': len([g for g in content_counts if g not in INFRASTRUCTURE]), 'sensitive_graphs_empty': len(SENSITIVE), 'rollback_directory': str(backup), 'source_data_replaced': False, 'automatic_checkpoint_minutes_restored': interval}
            (backup / '.ecoportal-public-refresh.json').write_text(json.dumps(result, indent=2))
            (backups / 'last-success.json').write_text(json.dumps(result, indent=2))
            owned_backups = [p for p in backups.iterdir() if p.is_dir() and not p.is_symlink() and (p / '.ecoportal-public-refresh.json').is_file()]
            for old in sorted(owned_backups, reverse=True)[3:]:
                shutil.rmtree(old)
            print(json.dumps(result), flush=True)
        except BaseException:
            if moved:
                subprocess.run(['systemctl', 'stop', 'virtuoso-public'], check=True, timeout=90)
                if old_safe and old_public <= current_public_subjects():
                    old = backup if backup.exists() else folder / 'db'
                    exchange_directories(PUBLIC, old)
                    os.rename(old, folder / 'failed-public')
                    subprocess.run(['systemctl', 'start', 'virtuoso-public'], check=True, timeout=90)
                    wait_public()
                    require({r['s']['value'] for r in rows(8891, ONTOLOGY)} == old_public and all(count(8891, g) == 0 for g in SENSITIVE), 'Rollback public validation failed')
            elif public_stopped and old_safe and old_public <= current_public_subjects():
                subprocess.run(['systemctl', 'start', 'virtuoso-public'], check=True, timeout=90)
                wait_public()
            elif not old_public <= current_public_subjects():
                subprocess.run(['systemctl', 'stop', 'virtuoso-public'], check=True, timeout=90)
            raise
        finally:
            stop_stage(child)
            sql(1111, 'checkpoint_interval (' + str(interval) + ');')
            shutil.rmtree(folder)


def exchange_directories(left, right):
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renameat2(-100, os.fsencode(left), -100, os.fsencode(right), 2) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def main():
    require(os.getuid() == 0 and socket.gethostname() in ('ecoportal-2026-dev', 'ecoportal-2026-prod'), 'Wrong host or user')
    require(SOURCE.resolve() == SOURCE and PUBLIC.resolve() == PUBLIC and PUBLIC.is_dir(), 'Unexpected native database paths')
    cfg = config(SOURCE_CONFIG)
    require(cfg['Database']['DatabaseFile'] == str(SOURCE) and cfg['Database']['Striping'] == '0', 'Unsupported private database layout')
    require(config(PUBLIC_CONFIG)['Database']['DatabaseFile'] == str(PUBLIC / 'virtuoso.db'), 'Unexpected public database configuration')
    interval = int(cfg['Parameters']['CheckpointInterval'])
    require(interval > 0, 'Invalid configured checkpoint interval')
    if sys.argv[1:] == ['--restore-checkpoint']:
        sql(1111, 'checkpoint_interval (' + str(interval) + ');')
    elif sys.argv[1:] == ['--refresh']:
        def interrupted(signum, frame):
            raise InterruptedError('Refresh interrupted')
        signal.signal(signal.SIGTERM, interrupted)
        refresh(interval)
    else:
        raise SystemExit('Usage: refresh_public_sparql.py --refresh | --restore-checkpoint')


if __name__ == '__main__':
    main()
