class AddResponseToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :response, :text
  end
end
