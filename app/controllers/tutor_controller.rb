class TutorController < ApplicationController
  require 'net/http'
  require 'json'

  skip_before_action :verify_authenticity_token, only: [:ask]

  def chat
    @subject = params[:subject] || 'general'
  end

  def ask
    begin
      question = params[:question]
      subject = params[:subject]

      session[:tutor_session_id] ||= SecureRandom.hex(16)

      # Get response from Claude API, with debug info
      response, debug_info = get_claude_response_with_debug(question, subject)

      # Save to database
      conversation = Conversation.create!(
        session_id: session[:tutor_session_id],
        subject: subject,
        question: question,
        response: response
      )

      render json: {
        question: question,
        response: response,
        debug: debug_info,
        success: true
      }
    rescue => e
      render json: {
        error: e.message,
        success: false
      }
    end
  end

  # Enhanced version for debugging API issues
  def get_claude_response_with_debug(question, subject)
    conversation_history = get_conversation_history(subject)
    messages = build_conversation_messages(conversation_history, question, subject)
    system_prompt = build_system_prompt(subject)
    claude_response, debug_info = call_claude_api_with_context_debug(messages, system_prompt)
    if claude_response && !claude_response.empty?
      return [claude_response, debug_info]
    end
    ["I'm having trouble connecting to my AI brain right now. Please try asking your question again in a moment!", debug_info]
  end
  end

  private

  def get_claude_response(question, subject)
    # Get conversation history for this session and subject
    conversation_history = get_conversation_history(subject)

    # Build the full conversation context
    messages = build_conversation_messages(conversation_history, question, subject)

    # Try the API call with full context
    claude_response = call_claude_api_with_context(messages)

    # Return response or fallback
    if claude_response && !claude_response.empty?
      return claude_response
    end

    "I'm having trouble connecting to my AI brain right now. Please try asking your question again in a moment!"
  end

  def get_conversation_history(subject)
    # Get the last 10 conversation pairs for this session and subject
    Conversation.where(
      session_id: session[:tutor_session_id],
      subject: subject
    ).order(:created_at).limit(20) # Last 10 Q & A pairs = 20 total
  end

  def build_conversation_messages(history, current_question, subject)
    messages = []

    # Add conversation history
    history.each do |conversation|
      messages << {
        role: "user",
        content: conversation.question
      }
      messages << {
        role: "assistant",
        content: conversation.response
      }
    end

    # Add current question
    messages << {
      role: "user",
      content: current_question
    }

    messages
  end

  def build_system_prompt(subject)
    "You are a friendly, encouraging AI tutor specifically designed for 6th grade students (ages 11-12). You are helping with #{subject}.

Key instructions:
- Remember our entire conversation and refer back to previous questions/answers
- If you asked a question in a previous response, acknowledge their answer
- Build on what you've already discussed together
- Use simple, age-appropriate language that a 6th grader can understand
- Be encouraging and positive in your tone
- Break down complex concepts into easy-to-follow steps
- Use relatable examples from a 6th grader's world (school, sports, movies, etc.)
- Keep responses concise but thorough (2-4 short paragraphs)
- If this seems like a homework question, guide them toward the answer rather than giving it directly
- Ask follow-up questions to keep them engaged and check understanding
- Reference previous parts of our conversation when relevant

Remember: You're having an ongoing conversation with a curious 6th grader, so maintain context and continuity!"
  end

  def call_claude_api_with_context_debug(messages, system_prompt = nil)
    begin
      uri = URI('https://api.anthropic.com/v1/messages')

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['x-api-key'] = ENV['ANTHROPIC_API_KEY']
      request['anthropic-version'] = '2023-06-01'

      # Add system prompt as top-level parameter
      body = {
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 1000,
        messages: messages,
        system: system_prompt
      }

      request.body = body.to_json

      response = http.request(request)

      Rails.logger.info "Claude API Status: #{response.code}"
      Rails.logger.info "Conversation Context: #{messages.length} messages"

      debug_info = {
        status: response.code,
        response_body: response.body[0..500],
        request_body: body,
        headers: request.to_hash
      }

      if response.code == '200'
        begin
          data = JSON.parse(response.body)
          claude_text = data.dig("content", 0, "text")

          if claude_text && !claude_text.empty?
            Rails.logger.info "SUCCESS: Got contextual Claude response"
            return [claude_text, debug_info]
          else
            Rails.logger.error "ERROR: Claude response was empty"
            debug_info[:error] = "Claude response was empty"
            return [nil, debug_info]
          end

        rescue JSON::ParserError => e
          Rails.logger.error "JSON Parse Error: #{e.message}"
          debug_info[:error] = "JSON Parse Error: #{e.message}"
          return [nil, debug_info]
        end
      else
        Rails.logger.error "API Error #{response.code}: #{response.body}"
        debug_info[:error] = "API Error #{response.code}: #{response.body}"
        return [nil, debug_info]
      end

    rescue => e
      Rails.logger.error "API Exception: #{e.class} - #{e.message}"
      return [nil, { error: "API Exception: #{e.class} - #{e.message}" }]
    end
  end

  def call_claude_api(prompt)
    begin
      uri = URI('https://api.anthropic.com/v1/messages')

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['x-api-key'] = ENV['ANTHROPIC_API_KEY']
      request['anthropic-version'] = '2023-06-01'

      body = {
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 1000,
        messages: [{
          role: "user",
          content: prompt
        }]
      }

      request.body = body.to_json

      response = http.request(request)

      Rails.logger.info "Claude API Status: #{response.code}"
      Rails.logger.info "Claude API Response: #{response.body[0..300]}..."

      if response.code == '200'
        begin
          data = JSON.parse(response.body)
          claude_text = data.dig("content", 0, "text")

          if claude_text && !claude_text.empty?
            Rails.logger.info "SUCCESS: Got Claude response of #{claude_text.length} characters"
            return claude_text
          else
            Rails.logger.error "ERROR: Claude response was empty or malformed"
            return nil
          end

        rescue JSON::ParserError => e
          Rails.logger.error "JSON Parse Error: #{e.message}"
          return nil
        end
      else
        Rails.logger.error "API Error #{response.code}: #{response.body}"
        return nil
      end

    rescue => e
      Rails.logger.error "API Exception: #{e.class} - #{e.message}"
      return nil
    end
  end

  def build_tutor_prompt(question, subject)
    "You are a friendly, encouraging AI tutor specifically designed for 6th grade students (ages 11-12). The student is asking about #{subject}.

Student's question: '#{question}'

Please provide a helpful, educational response following these guidelines:
- Use simple, age-appropriate language that a 6th grader can understand
- Be encouraging and positive in your tone
- Break down complex concepts into easy-to-follow steps
- Use relatable examples from a 6th grader's world (school, sports, movies, etc.)
- Keep your response concise but thorough (2-4 short paragraphs)
- If this seems like a homework question, guide them toward the answer rather than giving it directly
- End with an encouraging follow-up question to keep them engaged

Remember: You're helping a curious 6th grader learn, so make it fun and accessible!"
  end
