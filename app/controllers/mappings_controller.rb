require 'MappingLoader'
class MappingsController < ApplicationController
 

  # GET /mappings/new
  
  layout 'ontology'
  before_filter :authorize, :only=>[:create,:new]
  
  def index
    ontology_list = DataAccess.getOntologyList() # -- Gets list of ontologies
    mapped_ontologies_ids = ActiveRecord::Base.connection().execute("SELECT distinct(source_ont) as count from mappings")
    mapped_ontologies=[]
    mapped_ontologies_ids.each_hash(with_table=false) {|x| mapped_ontologies<<x['count']}
    @ontologies=[]

    for ontology in ontology_list
      if mapped_ontologies.include?(ontology.ontologyId)
        @ontologies << ontology
      end
    end

  end
  
  def service
    ontology = DataAccess.getOntology(params[:ontology])
    
    if params[:id]
      concept = DataAccess.getNode(ontology.id,params[:id])    
      from =[]
      to = []
      from_res = ActiveRecord::Base.connection().execute("SELECT * from mappings  where source_ont =#{ontology.ontologyId} AND source_id = '#{concept.id}'")
      from_res.each_hash(with_table=false) {|x| from<<x}

      to_res = ActiveRecord::Base.connection().execute("SELECT * from mappings  where destination_ont =#{ontology.ontologyId} AND destination_id = '#{concept.id}'")
      to_res.each_hash(with_table=false) {|x| to<<x}

    else
      from=[]
      to=[]
      from_res = ActiveRecord::Base.connection().execute("SELECT * from mappings  where source_ont =#{ontology.ontologyId} ")
      to_res = ActiveRecord::Base.connection().execute("SELECT * from mappings  where destination_ont =#{ontology.ontologyId}")
      from_res.each_hash(with_table=false) {|x| from<<x}
      to_res.each_hash(with_table=false) {|x| to<<x}

    end
  
    puts from.inspect
    puts to.inspect
    mappings = {:mapping_from=>from,:mapping_to=>to}
    
    render :xml=> mappings
  end
  
  def ontology_service
    
  end
  
  
  def count
    ontology = DataAccess.getOntology(params[:ontology])
    
    @ontology_id=ontology.ontologyId
    
    @source_counts =[]
    names = ActiveRecord::Base.connection().execute("SELECT count(id) as count,destination_ont,destination_ont_name,source_ont_name from mappings  where source_ont =#{ontology.ontologyId}  group by destination_ont")
     names.each_hash(with_table=false) {|x| @source_counts<<x}
    
    @dest_counts = []
    names = ActiveRecord::Base.connection().execute("SELECT count(id) as count,source_ont,destination_ont_name,source_ont_name from mappings  where destination_ont = #{ontology.ontologyId} group by source_ont")
    names.each_hash(with_table=false) {|x| @dest_counts<<x} 
    
    render :partial =>'count'
  end
  
  def show
    #Select *, count(*) as count from mappings where source_ont = 'NCI Thesaurus' and destination_ont = 'Mouse adult gross anatomy' group by destination_id order by count desc limit 100 OFFSET 0 
    @ontology = params[:id]
    @destination_ont=params[:target]
    
    
    expanded_query = ""
    if !params[:user].nil? && !params[:user].empty?
      expanded_query << " AND user_id = #{params[:user]} "
    end
    if !params[:map_source].nil? && !params[:map_source].empty?
      expanded_query << " AND map_source like '%#{params[:map_source]}%'"
    end
    
    @mapping_pages = Mapping.paginate_by_sql("Select source_id, count(*) as count from mappings where source_ont = '#{params[:id]}' and destination_ont = '#{params[:target]}' #{expanded_query} group by source_id order by count desc",:page => params[:page], :per_page => 100,:include=>'users')
  
    if params[:rdf].nil?
    mapping_objects = Mapping.find(:all,:conditions=>["source_ont = '#{params[:id]}' AND destination_ont = '#{params[:target]}' AND source_id IN (?) #{expanded_query}",@mapping_pages.collect{|item| item[:source_id]}.flatten])
  else
    mapping_objects =  Mapping.find(:all,:conditions=>["source_ont = '#{params[:id]}' AND destination_ont = '#{params[:target]}'  #{expanded_query}"])
  end
  
#    @mapping_pages = Mapping.paginate(:page => params[:page], :per_page => 100 ,:conditions=>{:source_ont=>params[:id],:destination_ont=>params[:target]},:order=>'count()',:include=>:user)
    @mappings = {}
    @map_sources = []
    @users = DataAccess.getUsers.sort{|x,y| x.username.downcase <=> y.username.downcase}
    for map in mapping_objects

      @map_sources << map.map_source.gsub(/<a.*?a>/mi, "")  unless map.map_source.nil?
      @map_sources.uniq!
      
      if @mappings[map.source_id].nil?
        @mappings[map.source_id] = [{:source_ont_name=>map.source_ont_name,:destination_ont_name=>map.destination_ont_name,:source_ont=>map.source_ont,:source_name=>map.source_name,:destination_ont=>map.destination_ont,:destination_name=>map.destination_name,:destination_id=>map.destination_id,:users=>[map.user.username],:count=>1}]
      else
        @mappings[map.source_id]
        found = false
        for mapping in @mappings[map.source_id]

          if mapping[:destination_id].eql?(map.destination_id)
            found = true
            mapping[:users]<<map.user.username
            mapping[:users].uniq!
            mapping[:count]+= 1
          end  
        end
        unless found
         @mappings[map.source_id]<< {:source_ont_name=>map.source_ont_name,:destination_ont_name=>map.destination_ont_name,:source_ont=>map.source_ont,:source_name=>map.source_name,:destination_ont=>map.destination_ont,:destination_name=>map.destination_name,:destination_id=>map.destination_id,:users=>[map.user.username],:count=>1}
        end
      end
    end
    @mappings = @mappings.sort {|a,b| b[1].length<=>a[1].length}   #=> [["c", 10], ["a", 20], ["b", 30]]

    if params[:rdf].nil? || !params[:rdf].eql?("rdf")
      render :partial=>'show'
    else
      send_data to_RDF(mapping_objects), :type => 'text/html', :disposition => 'attachment; filename=mappings.rdf'
    end
  end
  
  def upload
    @ontologies = @ontologies = DataAccess.getOntologyList()
    @users = User.find(:all)
  end
  
  
  def process_mappings
    
    
    
      MappingLoader.processMappings(params)
    
     flash[:notice] = 'Mappings are processed'
     @ontologies = @ontologies = DataAccess.getOntologyList()
     @users = User.find(:all)
     render :action=>:upload
  end
  
  def new
    ontology = DataAccess.getOntology(params[:ontology])
    @mapping = Mapping.new
    @mapping.source_id = params[:source_id]
    @mapping.source_ont = ontology.ontologyId
    @mapping.source_version_id=ontology.id
    @ontologies = DataAccess.getActiveOntologies() #populates dropdown
    @name = params[:source_name] #used for display
    
    render :layout=>false
  end

  # POST /mappings
  # POST /mappings.xml
  def create
    #creates mapping
    @mapping = Mapping.new(params[:mapping])
    
    destination_ontology = DataAccess.getOntology(@mapping.destination_version_id)
    

    @mapping.user_id = session[:user].id
    @mapping.source_name=DataAccess.getNode(@mapping.source_version_id,@mapping.source_id).name
    @mapping.source_ont_name = DataAccess.getOntology(@mapping.source_version_id).displayLabel
    @mapping.destination_name=DataAccess.getNode(@mapping.destination_version_id,@mapping.destination_id).name
    @mapping.destination_ont_name = destination_ontology.displayLabel
    @mapping.destination_ont = destination_ontology.ontologyId
    @mapping.save
    
    if params[:bidirectional].eql?("on")
      reverse = Mapping.new
      reverse.user_id = session[:user].id
      reverse.source_id = @mapping.destination_id
      reverse.destination_id = @mapping.source_id   
      reverse.source_version_id = @mapping.destination_version_id   
      reverse.destination_version_id = @mapping.source_version_id
      reverse.source_ont = @mapping.destination_ont
      reverse.source_name = @mapping.destination_name
      reverse.source_ont_name = @mapping.destination_ont_name
      reverse.destination_name = @mapping.source_name
      reverse.destination_ont_name = @mapping.source_ont_name
      reverse.destination_ont = @mapping.source_ont
      reverse.save
      
    end
        
    
    #repopulates table
    @mappings =  Mapping.find(:all, :conditions=>{:source_ont => @mapping.source_ont, :source_id => @mapping.source_id})
    @ontology = DataAccess.getOntology(@mapping.source_version_id)
    
    
    #adds mapping to syndication
    event = EventItem.new
    event.event_type="Mapping"
    event.event_type_id=@mapping.id
    event.ontology_id= @mapping.source_ont
    event.save
    
    
    
    render :partial =>'mapping_table'
     

  end

private

  def to_RDF(mappings)
    rdf_text = "<?xml version='1.0' encoding='UTF-8'?>


     <!DOCTYPE rdf:RDF [
         <!ENTITY xsd 'http://www.w3.org/2001/XMLSchema#' >
         <!ENTITY a 'http://protege.stanford.edu/system#' >
         <!ENTITY rdfs 'http://www.w3.org/2000/01/rdf-schema#' >
         <!ENTITY mappings 'http://protege.stanford.edu/mappings#' >
         <!ENTITY rdf 'http://www.w3.org/1999/02/22-rdf-syntax-ns#' >
     ]>


     <rdf:RDF xmlns=\"http://bioontology.org/mappings/mappings.rdf#\"
          xml:base=\"http://bioontology.org/mappings/mappings.rdf\"
          xmlns:xsd=\"http://www.w3.org/2001/XMLSchema#\"
          xmlns:rdfs=\"http://www.w3.org/2000/01/rdf-schema#\"
          xmlns:mappings=\"http://protege.stanford.edu/mappings#\"
          xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">
         <rdf:Property rdf:about=\"&mappings;author\">
             <rdfs:domain rdf:resource=\"&mappings;Mapping_Metadata\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
             <rdfs:label rdf:datatype=\"&xsd;string\">author</rdfs:label>
         </rdf:Property>
         <rdf:Property rdf:about=\"&mappings;comment\">
             <rdfs:domain rdf:resource=\"&mappings;Mapping_Metadata\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
              <rdfs:label rdf:datatype=\"&xsd;string\">comment</rdfs:label>
         </rdf:Property>
         <rdf:Property rdf:about=\"&mappings;confidence\">
             <rdfs:domain rdf:resource=\"&mappings;Mapping_Metadata\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
             <rdfs:label rdf:datatype=\"&xsd;string\">confidence</rdfs:label>
         </rdf:Property>
         <rdf:Property rdf:about=\"&mappings;date\">
             <rdfs:domain rdf:resource=\"&mappings;Mapping_Metadata\"/>
             <rdfs:range rdf:resource=\"&xsd;date\"/>
             <rdfs:label rdf:datatype=\"&xsd;string\">date</rdfs:label>
         </rdf:Property>
         <rdfs:Class rdf:about=\"&mappings;Mapping_Metadata\">
             <rdfs:label rdf:datatype=\"&xsd;string\"
                 >Mapping_Metadata</rdfs:label>
         </rdfs:Class>
         <rdf:Property rdf:about=\"&mappings;mapping_metadata\">
             <rdfs:domain rdf:resource=\"&mappings;One_to_one_mapping\"/>
             <rdfs:range rdf:resource=\"&mappings;Mapping_Metadata\"/>
              <rdfs:label rdf:datatype=\"&xsd;string\"
                 >mapping_metadata</rdfs:label>
         </rdf:Property>
         <rdf:Property rdf:about=\"&mappings;mapping_source\">
             <rdfs:domain rdf:resource=\"&mappings;Mapping_Metadata\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
              <rdfs:label rdf:datatype=\"&xsd;string\">authority</rdfs:label>
         </rdf:Property>
         <rdfs:Class rdf:about=\"&mappings;One_to_one_mapping\">
             <rdfs:label rdf:datatype=\"&xsd;string\"
                 >One_to_one_mapping</rdfs:label>
         </rdfs:Class>
         <rdf:Property rdf:about=\"&mappings;relation\">
             <rdfs:domain rdf:resource=\"&mappings;One_to_one_mapping\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
              <rdfs:label rdf:datatype=\"&xsd;string\">relation</rdfs:label>
         </rdf:Property>
         <rdf:Property rdf:about=\"&mappings;source\">
             <rdfs:domain rdf:resource=\"&mappings;One_to_one_mapping\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
             <rdfs:label rdf:datatype=\"&xsd;string\">source</rdfs:label>
         </rdf:Property>
         <rdf:Property rdf:about=\"&mappings;target\">
             <rdfs:domain rdf:resource=\"&mappings;One_to_one_mapping\"/>
             <rdfs:range rdf:resource=\"&xsd;string\"/>
             <rdfs:label rdf:datatype=\"&xsd;string\">target</rdfs:label>
         </rdf:Property>"
         
         count = 1
         
         for mapping in mappings
          rdf_text << "<mappings:One_to_one_mapping rdf:ID=\"#{count}\">
             <mappings:mapping_metadata rdf:resource=\"##{count+1}\"/>
             <mappings:relation rdf:datatype=\"&xsd;string\">#{mapping.relationship_type}</mappings:relation>
             <mappings:source rdf:resource='http://bioportal.bioontology.org/#{to_param(mapping.source_ont)}/#{mapping.source_id}'/>
             <mappings:target rdf:resource='http://bioportal.bioontology.org/#{to_param(mapping.destination_ont)}/#{mapping.destination_id}'/>
         </mappings:One_to_one_mapping>
         <mappings:Mapping_Metadata rdf:ID=\"#{count+1}\">
             <mappings:author rdf:datatype=\"&xsd;string\">#{mapping.user.username}</mappings:author>
             <mappings:mapping_source rdf:datatype=\"&xsd;string\">#{mapping.map_source}</mappings:mapping_source>
             <mappings:comment rdf:datatype=\"&xsd;string\">#{mapping.comment}</mappings:comment>
             <mappings:date rdf:datatype=\"&xsd;date\">#{mapping.created_at}</mappings:date>
         </mappings:Mapping_Metadata>"
         
         count +=2
         
        end
         
         
     rdf_text << "</rdf:RDF>"
     return rdf_text
  end


end
