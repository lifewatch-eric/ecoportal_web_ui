class ReplyNotificationMailer < ApplicationMailer
  def reply_to_comment(creator_email, reply, parent_note, replier_username)
    @reply = reply
    @parent_note = parent_note
    @replier_username = replier_username

    mail(
      to: creator_email,
      subject: "New reply to your note: #{parent_note.subject}"
    )
  end
end
