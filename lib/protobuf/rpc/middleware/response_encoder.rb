module Protobuf
  module Rpc
    module Middleware
      class ResponseEncoder
        include ::Protobuf::Logging

        attr_reader :app, :env

        def initialize(app)
          @app = app
        end

        def call(env)
          @env = app.call(env)

          env.response = response
          env.encoded_response = encoded_response
          env
        end

        def log_signature
          env.log_signature || super
        end

        private

        # Encode the response wrapper to return to the client
        #
        def encoded_response
          logger.debug { sign_message("Encoding response: #{response.inspect}") }

          env.encoded_response = wrapped_response.encode
        rescue => exception
          log_exception(exception)

          # Rescue encoding exceptions, re-wrap them as generic protobuf errors,
          # and re-raise them
          raise PbError, exception.message
        end

        # Prod the object to see if we can produce a proto object as a response
        # candidate. Validate the candidate protos.
        def response
          @response ||= begin
                          candidate = env.response
                          case
                          when candidate.is_a?(Message) then
                            validate!(candidate)
                          when candidate.respond_to?(:to_proto) then
                            validate!(candidate.to_proto)
                          when candidate.respond_to?(:to_hash) then
                            env.response_type.new(candidate.to_hash)
                          when candidate.is_a?(PbError) then
                            candidate
                          else
                            validate!(candidate)
                          end
                        end
        end

        # Ensure that the response candidate we've been given is of the type
        # we expect so that deserialization on the client side works.
        #
        def validate!(candidate)
          actual = candidate.class
          expected = env.response_type

          if expected != actual
            fail BadResponseProto, "Expected response to be of type #{expected.name} but was #{actual.name}"
          end

          candidate
        end

        # The middleware stack returns either an error or response proto. Package
        # it up so that it's in the correct spot in the response wrapper
        #
        def wrapped_response
          if response.is_a?(Protobuf::Rpc::PbError)
            Socketrpc::Response.new(:error => response.message, :error_reason => response.error_type)
          else
            Socketrpc::Response.new(:response_proto => response.encode)
          end
        end
      end
    end
  end
end
