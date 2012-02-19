require 'rubygems'
require 'sinatra/async'
require 'thin'
require 'json'

class Search < Sinatra::Base
  register Sinatra::Async

  class JSONStream
    include EventMachine::Deferrable

    def stream(object)
      @block.call object.to_json + "\n"
    end

    def each(&block)
      @block = block
    end
  end

  aget '/process' do
    puts 'ok'
    out = JSONStream.new
    body out
    EM.next_tick do
      c = 0
      timer = EM.add_periodic_timer(0.3) do
        c += 1
        out.stream :data => ["this is part #{c}"]
        if c == 100
          timer.cancel
          out.succeed
        end
      end
    end
  end

  run!
end
