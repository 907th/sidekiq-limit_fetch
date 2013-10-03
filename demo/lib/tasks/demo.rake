namespace :demo do
  task limit: :environment do
    puts '=> Creating sidekiq tasks'

    100.times do
      SlowWorker.perform_async
      FastWorker.perform_async
    end

    run_sidekiq_monitoring
    run_sidekiq_workers config: <<-YAML
      :verbose: false
      :concurrency: 4
      :queues:
        - slow
        - fast
      :limits:
        slow: 1
    YAML
  end

  def with_sidekiq_config(config)
    whitespace_offset = config[/\A */].size
    config.gsub! /^ {#{whitespace_offset}}/, ''

    puts "=> Use sidekiq config:\n#{config}"
    File.write 'config/sidekiq.yml', config
    yield
  ensure
    FileUtils.rm 'config/sidekiq.yml'
  end

  def run_sidekiq_monitoring
    require 'sidekiq/web'
    Thread.new do
      Rack::Server.start app: Sidekiq::Web, Port: 3000
    end
    sleep 1
    Launchy.open 'http://127.0.0.1:3000/workers?poll=true'
  end

  def run_sidekiq_workers(options)
    require 'sidekiq/cli'
    cli = Sidekiq::CLI.instance

    %w(validate! boot_system).each do |stub|
      cli.define_singleton_method(stub) {}
    end

    with_sidekiq_config options[:config] do
      config = cli.send :parse_config, 'config/sidekiq.yml'
      Sidekiq.options.merge! config
    end

    cli.run
  end
end
