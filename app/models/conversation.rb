class Conversation < ApplicationRecord

  validates :session_id, presence: true
  validates :subject, presence: true
  validates :question, presence: true
  
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :by_subject, ->(subject) { where(subject: subject) }

end
