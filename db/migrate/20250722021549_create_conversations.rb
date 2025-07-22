class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.string :session_id
      t.string :subject
      t.string :question

      t.timestamps
    end
  end
end
