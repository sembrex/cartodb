# encoding: utf-8

require 'typhoeus'
require 'socket'

module Carto
  # Wrapper on top of Typhoeus
  class HttpClient

    def initialize(tag)
      hostname = Socket.gethostname
      @logger = ResponseLogger.new(tag, hostname)
    end

    # Returns a wrapper to a typhoeus request object
    def request(url, options = {})
      Request.new(@logger, url, options)
    end

    def get(url, options = {})
      request = Request.new(@logger, url, options.merge(method: :get))
      request.run
    end

    def post(url, options = {})
      request = Request.new(@logger, url, options.merge(method: :post))
      request.run
    end

    def head(url, options = {})
      request = Request.new(@logger, url, options.merge(method: :head))
      request.run
    end

    def put(url, options = {})
      request = Request.new(@logger, url, options.merge(method: :put))
      request.run
    end

    def delete(url, options = {})
      request = Request.new(@logger, url, options.merge(method: :delete))
      request.run
    end


    private


    class Request

      def initialize(logger, url, options = {})
        @logger = logger
        @typhoeus_request = Typhoeus::Request.new(url, options)
      end

      def run
        response = @typhoeus_request.run
        @logger.log(response)
        response
      end

      def url
        @typhoeus_request.url
      end

      def options
        @typhoeus_request.options
      end
    end


    class ResponseLogger
      def initialize(tag, hostname)
        @tag = tag
        @hostname = hostname
      end

      def log(response)
        payload = {
          tag: @tag,
          hostname: @hostname,
          method: response.request.options[:method].to_s,
          request_url: response.request.url,
          total_time: response.total_time,
          response_code: response.code,
          response_body_size: response.body.nil? ? 0 : response.body.size
        }
        logger.info(payload.to_json)
      end

      def logger
        @@logger ||= Logger.new("#{Rails.root}/log/http_client.log")
      end

    end

  end
end
