class ReplyNotificationMailer < ApplicationMailer
  def reply_to_comment(creator_email, reply, parent_resource, replier_username)
    @reply = reply
    @parent_resource = parent_resource
    @replier_username = replier_username

    mail(
      to: creator_email,
      from: $SUPPORT_EMAIL,
      subject: "New reply to your #{parent_resource_name}: #{parent_resource_title}"
    )
  end

  private

  def parent_resource_name
    @parent_resource.is_a?(LinkedData::Client::Models::Note) ? 'note' : 'reply'
  end

  def parent_resource_title
    @parent_resource.subject.presence || @parent_resource.body.to_s.tr("\n", ' ').truncate(80)
  end
end
