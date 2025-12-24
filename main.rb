require 'net/http'
require 'uri'
require 'json'
require 'securerandom'

API_KEY = "<your_api_key>"
BASE_URL = "https://api.on-demand.io/chat/v1"

EXTERNAL_USER_ID = "<your_external_user_id>"
QUERY = "<your_query>"
RESPONSE_MODE = "" # Now dynamic
AGENT_IDS = [] # Dynamic array from PluginIds
ENDPOINT_ID = "predefined-openai-gpt4.1"
REASONING_MODE = "grok-4-fast"
FULFILLMENT_PROMPT = ""
STOP_SEQUENCES = [] # Dynamic array
TEMPERATURE = 0.7
TOP_P = 1
MAX_TOKENS = 0
PRESENCE_PENALTY = 0
FREQUENCY_PENALTY = 0

ContextField = Struct.new(:key, :value)

class SessionData
  attr_accessor :id, :context_metadata

  def initialize(id, context_metadata)
    @id = id
    @context_metadata = context_metadata
  end
end

class CreateSessionResponse
  attr_accessor :data

  def initialize(data)
    @data = data
  end
end

def main
  if API_KEY == "<your_api_key>" || API_KEY.empty?
    puts "❌ Please set API_KEY."
    exit 1
  end
  external_user_id = EXTERNAL_USER_ID
  if external_user_id == "<your_external_user_id>" || external_user_id.empty?
    external_user_id = SecureRandom.uuid
    puts "⚠️  Generated EXTERNAL_USER_ID: #{external_user_id}"
  end

  context_metadata = [
    { "key" => "userId", "value" => "1" },
    { "key" => "name", "value" => "John" }
  ]

  session_id = create_chat_session(external_user_id)
  if !session_id.empty?
    puts "\n--- Submitting Query ---"
    puts "Using query: '#{QUERY}'"
    puts "Using responseMode: '#{RESPONSE_MODE}'"
    submit_query(session_id, context_metadata) # 👈 updated
  end
end

def create_chat_session(external_user_id)
  url = URI.parse("#{BASE_URL}/sessions")

  context_metadata = [
    { "key" => "userId", "value" => "1" },
    { "key" => "name", "value" => "John" }
  ]

  body = {
    "agentIds" => AGENT_IDS,
    "externalUserId" => external_user_id,
    "contextMetadata" => context_metadata
  }

  json_body = body.to_json

  puts "📡 Creating session with URL: #{url}"
  puts "📝 Request body: #{json_body}"

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(url.request_uri)
  request["apikey"] = API_KEY
  request["Content-Type"] = "application/json"
  request.body = json_body

  response = http.request(request)

  if response.code.to_i == 201
    session_resp_data = JSON.parse(response.body)
    context_metadata_parsed = session_resp_data["data"]["contextMetadata"].map { |field| ContextField.new(field["key"], field["value"]) }
    session_data = SessionData.new(session_resp_data["data"]["id"], context_metadata_parsed)
    session_resp = CreateSessionResponse.new(session_data)

    puts "✅ Chat session created. Session ID: #{session_resp.data.id}"

    if !session_resp.data.context_metadata.empty?
      puts "📋 Context Metadata:"
      session_resp.data.context_metadata.each do |field|
        puts " - #{field.key}: #{field.value}"
      end
    end

    return session_resp.data.id
  else
    puts "❌ Error creating chat session: #{response.code} - #{response.body}"
    return ""
  end
end

def submit_query(session_id, context_metadata)
  url = URI.parse("#{BASE_URL}/sessions/#{session_id}/query")

  body = {
    "endpointId" => ENDPOINT_ID,
    "query" => QUERY,
    "agentIds" => AGENT_IDS,
    "responseMode" => RESPONSE_MODE,
    "reasoningMode" => REASONING_MODE,
    "modelConfigs" => {
      "fulfillmentPrompt" => FULFILLMENT_PROMPT,
      "stopSequences" => STOP_SEQUENCES,
      "temperature" => TEMPERATURE,
      "topP" => TOP_P,
      "maxTokens" => MAX_TOKENS,
      "presencePenalty" => PRESENCE_PENALTY,
      "frequencyPenalty" => FREQUENCY_PENALTY
    }
  }

  json_body = body.to_json

  puts "🚀 Submitting query to URL: #{url}"
  puts "📝 Request body: #{json_body}"

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(url.request_uri)
  request["apikey"] = API_KEY
  request["Content-Type"] = "application/json"
  request.body = json_body

  puts ""

  if RESPONSE_MODE == "sync"
    response = http.request(request)

    if response.code.to_i == 200
      original = JSON.parse(response.body)

      # Append context metadata at the end
      original["data"]["contextMetadata"] = context_metadata if original["data"]

      final = JSON.pretty_generate(original)
      puts "✅ Final Response (with contextMetadata appended):"
      puts final
    else
      puts "❌ Error submitting sync query: #{response.code} - #{response.body}"
    end
  elsif RESPONSE_MODE == "stream"
    puts "✅ Streaming Response..."

    response = http.request(request)

    if response.code.to_i != 200
      puts "❌ Error submitting stream query: #{response.code} - #{response.body}"
      return
    end

    full_answer = ""
    final_session_id = ""
    final_message_id = ""
    metrics = {}

    response.read_body do |chunk|
      chunk.split("\n").each do |line|
        next unless line.start_with?("data:")

        data_str = line[5..].strip

        break if data_str == "[DONE]"

        begin
          event = JSON.parse(data_str)
          if event["eventType"] == "fulfillment"
            full_answer += event["answer"] if event["answer"]
            final_session_id = event["sessionId"] if event["sessionId"]
            final_message_id = event["messageId"] if event["messageId"]
          elsif event["eventType"] == "metricsLog"
            metrics = event["publicMetrics"] if event["publicMetrics"]
          end
        rescue JSON::ParserError
          next
        end
      end
    end

    final_response = {
      "message" => "Chat query submitted successfully",
      "data" => {
        "sessionId" => final_session_id,
        "messageId" => final_message_id,
        "answer" => full_answer,
        "metrics" => metrics,
        "status" => "completed",
        "contextMetadata" => context_metadata
      }
    }

    formatted = JSON.pretty_generate(final_response)
    puts "\n✅ Final Response (with contextMetadata appended):"
    puts formatted
  end
end

main
