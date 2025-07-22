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
      
      # Get response from Claude API
      response = get_claude_response(question, subject)
      
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
        success: true 
      }
    rescue => e
      render json: { 
        error: e.message,
        success: false 
      }
    end
  end
  
  private
  
  def get_claude_response(question, subject)
    prompt = build_tutor_prompt(question, subject)
    
    # Always try the real API first
    claude_response = call_claude_api(prompt)
    
    # Return the API response if we got one
    if claude_response && !claude_response.empty?
      return claude_response
    end
    
    # Only fall back if API completely fails
    "I'm having trouble connecting to my AI brain right now. Please try asking your question again in a moment!"
  end

  def call_claude_api(prompt)
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
      messages: [
        {
          role: "user",
          content: prompt
        }
      ]
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
end