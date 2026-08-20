require "faraday"
require "json"
require "cgi"

module ReleaseNotes
  class GitLogFetcher
    GITHUB_API_BASE = "https://api.github.com"
    REPO_URL_PATTERN = %r{\Ahttps?://(?:www\.)?github\.com/([\w.\-]+)/([\w.\-]+?)(?:\.git)?/?\z}
    MAX_COMMITS = 100

    class InvalidRepoUrlError < StandardError; end
    class FetchError < StandardError; end

    # @param repo_url [String] Public GitHub URL, e.g. "https://github.com/owner/repo"
    # @param from_ref [String] Base ref (tag, branch, SHA), e.g. "v1.0.0"
    # @param to_ref [String] Head ref, e.g. "v1.1.0" or "main"
    def initialize(repo_url:, from_ref:, to_ref:)
      @repo_url = repo_url.to_s.strip
      @from_ref = from_ref.to_s.strip
      @to_ref = to_ref.to_s.strip
    end

    # @return [String] Formatted commit list ready to paste into AI rewriter
    def fetch!
      match = REPO_URL_PATTERN.match(@repo_url)
      raise InvalidRepoUrlError, "Invalid GitHub repo URL" unless match
      raise InvalidRepoUrlError, "from_ref is required" if @from_ref.blank?
      raise InvalidRepoUrlError, "to_ref is required" if @to_ref.blank?

      owner = match[1]
      repo = match[2]
      path = "/repos/#{owner}/#{repo}/compare/#{CGI.escape(@from_ref)}...#{CGI.escape(@to_ref)}"

      response = client.get(path)

      unless response.success?
        body = parse_body(response.body)
        message = body["message"] || "HTTP #{response.status}"
        raise FetchError, "GitHub API error: #{message}"
      end

      body = parse_body(response.body)
      commits = body["commits"] || []
      commits = commits.first(MAX_COMMITS)

      format_commits(commits)
    rescue Faraday::Error => e
      raise FetchError, "Network error: #{e.message}"
    end

    private

    def client
      @client ||= Faraday.new(url: GITHUB_API_BASE) do |f|
        f.request :retry, max: 2, interval: 0.5, backoff_factor: 2
        f.headers["Accept"] = "application/vnd.github+json"
        f.headers["X-GitHub-Api-Version"] = "2022-11-28"
        f.headers["User-Agent"] = "MySigner-ReleaseNotes"
        # Optional token from env for higher rate limit / private repos
        if (token = ENV["GITHUB_TOKEN"]).present?
          f.headers["Authorization"] = "Bearer #{token}"
        end
        f.options.timeout = 15
      end
    end

    def parse_body(body)
      return {} if body.blank?
      body.is_a?(String) ? JSON.parse(body) : body
    rescue JSON::ParserError
      {}
    end

    def format_commits(commits)
      lines = []
      commits.each do |commit|
        msg = commit.dig("commit", "message").to_s.lines.first.to_s.strip
        next if msg.blank?
        sha = commit["sha"].to_s[0, 7]
        lines << "- #{sha} #{msg}"
      end
      lines.join("\n")
    end
  end
end
