require 'grape'
require 'tracon/aws'
require 'tracon/engine'

module Tracon
  class API < Grape::API
    format :json

    head '/ping' do
      status 204
      ''
    end

    namespace :clusters do
      http_basic do |username, password|
        Thread.current[:aws_region] = env['HTTP_X_AWS_REGION'] || 'eu-west-1'
        Engine.valid_credentials?(username, password).tap do
          @cluster, @domain = username.split('.')
          if @domain.nil?
            @domain = @cluster
            @cluster = nil
          end
        end
      end

      desc 'Show all clusters.'
      get do
        Tracon::AWS.clusters(@domain)
      end

      route_param :cluster do
        desc 'Show a cluster.'
        get do
          cluster = Tracon::AWS.cluster(@domain, params[:cluster])
          if cluster.nil?
            status 404
          else
            cluster
          end
        end

        namespace :queues do
          desc 'Show all queues for cluster.'
          get do
            Tracon::AWS.queues(@domain, params[:cluster])
          end

          route_param :queue do
            desc 'Show a queue.'
            get do
              queue = Tracon::AWS.queue(@domain, params[:cluster], params[:queue])
              if queue.nil?
                status 404
              else
                queue
              end
            end

            desc 'Create a queue.'
            put do
              if @cluster != params[:cluster]
                status 401
                return
              end
              creator = Engine.creator(params.merge(domain: @domain))
              if creator.process
                status 202
                creator.queue
              else
                status 403
                {
                  status: 'fail',
                  errors: creator.errors
                }
              end
            end

            desc 'Remove a queue.'
            delete do
              if @cluster != params[:cluster]
                status 401
                return
              end
              destroyer = Engine.destroyer(params.merge(domain: @domain))
              if !destroyer.process
                status 403
                {
                  status: 'fail',
                  errors: destroyer.errors
                }
              else
                status 204
                ''
              end
            end

            desc 'Update queue size.'
            post do
              if @cluster != params[:cluster]
                status 401
                return
              end
              updater = Engine.updater(params.merge(domain: @domain))
              if updater.process
                status 202
                updater.queue
              else
                status 403
                {
                  status: 'fail',
                  errors: updater.errors
                }
              end
            end

            namespace :nodes do
              desc 'Show all nodes for queue.'
              get do
                Tracon::AWS.nodes(@domain, params[:cluster], params[:queue])
              end

              route_param :node do
                desc 'Show a node for queue.'
                get do
                  Tracon::AWS.node(@domain, params[:cluster], params[:queue], params[:node])
                end

                desc 'Shoot a node.'
                delete do
                  if @cluster != params[:cluster]
                    status 401
                    return
                  end
                  shooter = Engine.shooter(params.merge(domain: @domain))
                  if !shooter.process
                    status 403
                    {
                      status: 'fail',
                      errors: shooter.errors
                    }
                  else
                    status 204
                    ''
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
