require 'json'
require 'pry'
require 'fuzzystringmatch'

module Lita
  module Handlers
    class Trivia < Handler
      TRIVIA_API_URL = URI.parse('http://jservice.io/api/random')
      REDIS_TRIVIA_KEY = 'current_trivia'.freeze

      route(/trivia(?: me)?/i, :handle_trivia_request, command: true, help: {
        'trivia me' => 'asks for a question from the trivia API'
      })

      route(/solution(?: me)?/i, :handle_solution_request, command: true, help: {
        'solution me' => 'returns the answer for the question from the trivia API'
      })

      route(/answer\s+(.*)?/i, :handle_answer_request, command: true, help: {
        'answer <answer>' => 'determines whether <answer> is correct for the current question'
      })

      def handle_trivia_request(req)
        payload = Net::HTTP.get_response TRIVIA_API_URL
        redis.set REDIS_TRIVIA_KEY, payload.body
        title_and_question = Jeopardizer.title_and_question(redis)
        req.reply(title_and_question)
      end

      def handle_solution_request(req)
        answer = Jeopardizer.answer(redis)
        redis.del REDIS_TRIVIA_KEY
        req.reply answer
      end

      def handle_answer_request(req)
        res = Jeopardizer.try_answer(redis, req.match_data[1])
        redis.del REDIS_TRIVIA_KEY if res == :correct
        req.reply res
      end

      class Jeopardizer
        def self.title_and_question(redis)
          self.new(redis.get(REDIS_TRIVIA_KEY)).title_and_question
        end

        def self.answer(redis)
          return 'Please ask for another question' unless redis.exists REDIS_TRIVIA_KEY
          self.new(redis.get(REDIS_TRIVIA_KEY)).answer
        end

        def self.try_answer(redis, query)
          return 'Please ask for another question' unless redis.exists REDIS_TRIVIA_KEY
          self.new(redis.get(REDIS_TRIVIA_KEY)).try_answer(query)
        end

        attr_accessor :payload

        def initialize(payload)
          @payload = JSON.parse(payload, symbolize_names: true).first
        end

        def question
          payload[:question]
        end

        def category
          payload[:category][:title].capitalize
        end

        def title_and_question
          category + "\n" + question + "\n" + answer
        end

        def answer
          strip_html(payload[:answer])
        end

        def try_answer(query)
          correct?(query) ? :correct : :incorrect
        end

        private
        def strip_html(str)
          str.gsub(/<\/?[^>]*>/, "")
        end

        def correct?(query)
          jarow = FuzzyStringMatch::JaroWinkler.create(:native)
          jarow.getDistance(answer, query) > 0.8 ||
            jarow.getDistance(answer.split.last, query) > 0.8
        end
      end

      Lita.register_handler(self)
    end
  end
end
