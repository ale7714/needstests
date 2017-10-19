require "rest-client"

class Engine
  CODECLIMATE_API_URL = "https://api.codeclimate.com/v1/".freeze

  def initialize(github_slug:, options:, out: STDOUT)
    @github_slug = github_slug
    @options = options
    @out = out
  end

  def run
    puts repo
  end

  private

  attr_reader :github_slug, :options, :out

  def repo
    @repo ||= begin
      RestClient.get(
        "#{CODECLIMATE_API_URL}/repos?github_slug=#{github_slug}",
        { :Accept => "application/vnd.api+json",
          :Authorization => "Token token=#{options[:cc_token]}",
        }
      )
    end
  end

  def snapshot_id
    @snapshot ||= repo["relationships"]["latest_default_branch_snapshot"]["data"]["id"]
  end
end
