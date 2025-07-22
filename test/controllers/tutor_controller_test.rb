require "test_helper"

class TutorControllerTest < ActionDispatch::IntegrationTest
  test "should get chat" do
    get tutor_chat_url
    assert_response :success
  end

  test "should get ask" do
    get tutor_ask_url
    assert_response :success
  end
end
