class ReplyNotificationMailer < ApplicationMailer



  def reply_to_comment(creatorEmail,reply)
    @creatorEmail = creatorEmail
    @reply = reply
    mail(
      :to => creatorEmail,
      :from => $SUPPORT_EMAIL,
      :subject => "Re: #{reply.comment.title}",
      :body => "Dear #{@creatorEmail},\n\n#{@reply.user.name} has replied to your comment on the article \"#{reply.comment.title}\".\n\n#{@reply.content}\n\nBest regards,\nYour EcoPortal Team"
    )
    end


end
