require "rest-client"
require "json"

class Engine
  CODECLIMATE_API_URL = "https://api.codeclimate.com/v1/".freeze

  def initialize(github_slug:, options:, out: STDOUT)
    @github_slug = github_slug
    @options = options
    @out = out
  end

  def run
    issues.group_by { |i| i["attributes"]["constant_name"] }.each do |constant_name, issues|
      test_file_report = test_file_report_for(constant_name)
      issues.each do |issue|
        coverage = 0

        unless test_file_report.nil?
          coverage = coverage_for(test_file_report["attributes"]["coverage"],issue["attributes"]["location"]) || test_file_report["attributes"]["covered_percent"]
        end

        puts issue_for(issue["attributes"]["categories"], coverage, issue["attributes"]["location"], issue["attributes"]["severity"]).to_json
      end
    end
  end

  private

  attr_reader :github_slug, :options, :out

  def repo
    @repo ||= begin
      ::JSON.parse(
        RestClient.get(
          "#{CODECLIMATE_API_URL}/repos?github_slug=#{github_slug}",
          { :Accept => "application/vnd.api+json",
            :Authorization => "Token token=#{options[:cc_token]}",
          }
        )
      )["data"].first
    end
  end

  def issues
    @issues ||= begin
      ::JSON.parse(
        RestClient.get(
          "#{CODECLIMATE_API_URL}/repos/#{repo["id"]}/snapshots/#{snapshot_id}/issues",
          { :Accept => "application/vnd.api+json",
            :Authorization => "Token token=#{options[:cc_token]}",
            :params => {
              :filter => {
                :severity => { :$in => ["minor", "major", "critical"] },
                :categories => { :$in => ["Complexity", "Duplication"] },
              }
            },
          }
        )
      )["data"]
    end
  end

  def test_report
    @test_report ||= begin
      ::JSON.parse(
        RestClient.get(
          "#{CODECLIMATE_API_URL}/repos/#{repo["id"]}/test_reports",
          { :Accept => "application/vnd.api+json",
            :Authorization => "Token token=#{options[:cc_token]}",
            :params => {
              :filter => {
                :branch => repo["attributes"]["branch"],
              },
              :page => { :size => 1 },
            },
          }
        )
      )["data"].first
    end
  end

  def test_file_report_for(constant_name)
    return if test_report.nil?
    ::JSON.parse(
      RestClient.get(
        "#{CODECLIMATE_API_URL}/repos/#{repo["id"]}/test_reports/#{test_report["id"]}/test_file_reports",
        { :Accept => "application/vnd.api+json",
          :Authorization => "Token token=#{options[:cc_token]}",
          :params => {
            :filter => {
              :path => constant_name,
            }
          },
        }
      )
    )["data"].first
  end

  def issue_for(categories, covered, location, severity)
    {
      issue: {
        categories: categories,
        severity: severity,
      },
      coverage: "#{covered}%",
      risk: risk_for(covered),
      location: location,
    }
  end

  def coverage_for(coverage, location)
    if location["start_line"] && location["end_line"]
      start = location["start_line"] - 1
      last = location["end_line"] - 1
      coverage[start..last].reject{ |e| e.nil? || e.zero? }.count
    end
  end

  def risk_for(covered)
    if covered < 40
      "high"
    elsif covered < 70
      "medium"
    else
      "low"
    end
  end

  def snapshot_id
    repo["relationships"]["latest_default_branch_snapshot"]["data"]["id"]
  end
end
