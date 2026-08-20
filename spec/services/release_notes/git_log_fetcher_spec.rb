require "rails_helper"

RSpec.describe ReleaseNotes::GitLogFetcher do
  let(:repo_url) { "https://github.com/owner/repo" }
  let(:from_ref) { "v1.0.0" }
  let(:to_ref) { "v1.1.0" }

  let(:mock_connection) { instance_double(Faraday::Connection) }
  let(:mock_response) { instance_double(Faraday::Response) }

  before do
    allow(Faraday).to receive(:new).and_return(mock_connection)
  end

  def build_body(commits)
    { "commits" => commits }.to_json
  end

  def sample_commit(sha:, message:)
    {
      "sha" => sha,
      "commit" => { "message" => message }
    }
  end

  describe "URL parsing" do
    let(:ok_body) { build_body([ sample_commit(sha: "abcdef1234567", message: "feat: initial") ]) }

    before do
      allow(mock_connection).to receive(:get).and_return(mock_response)
      allow(mock_response).to receive(:success?).and_return(true)
      allow(mock_response).to receive(:body).and_return(ok_body)
    end

    it "accepts standard https github URLs" do
      fetcher = described_class.new(repo_url: "https://github.com/owner/repo", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.not_to raise_error
      expect(mock_connection).to have_received(:get).with(%r{/repos/owner/repo/compare/v1\.0\.0\.\.\.v1\.1\.0})
    end

    it "accepts URLs with .git suffix" do
      fetcher = described_class.new(repo_url: "https://github.com/owner/repo.git", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.not_to raise_error
      expect(mock_connection).to have_received(:get).with(%r{/repos/owner/repo/compare/})
    end

    it "accepts URLs with trailing slash" do
      fetcher = described_class.new(repo_url: "https://github.com/owner/repo/", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.not_to raise_error
    end

    it "accepts URLs with www subdomain" do
      fetcher = described_class.new(repo_url: "https://www.github.com/owner/repo", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.not_to raise_error
    end

    it "accepts http:// URLs (though they'll be upgraded by GitHub)" do
      fetcher = described_class.new(repo_url: "http://github.com/owner/repo", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.not_to raise_error
    end

    it "strips leading/trailing whitespace" do
      fetcher = described_class.new(repo_url: "  https://github.com/owner/repo  ", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.not_to raise_error
    end

    it "rejects non-github URLs" do
      fetcher = described_class.new(repo_url: "https://gitlab.com/owner/repo", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::InvalidRepoUrlError, /Invalid GitHub/)
    end

    it "rejects empty repo URL" do
      fetcher = described_class.new(repo_url: "", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::InvalidRepoUrlError)
    end

    it "rejects malformed repo URL" do
      fetcher = described_class.new(repo_url: "not-a-url", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::InvalidRepoUrlError)
    end

    it "rejects URL with only owner (no repo)" do
      fetcher = described_class.new(repo_url: "https://github.com/owner", from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::InvalidRepoUrlError)
    end

    it "rejects empty from_ref" do
      fetcher = described_class.new(repo_url: repo_url, from_ref: "", to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::InvalidRepoUrlError, /from_ref/)
    end

    it "rejects empty to_ref" do
      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: "")
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::InvalidRepoUrlError, /to_ref/)
    end
  end

  describe "successful fetch" do
    before do
      allow(mock_connection).to receive(:get).and_return(mock_response)
      allow(mock_response).to receive(:success?).and_return(true)
    end

    it "returns formatted commits with short SHA and first message line" do
      body = build_body([
        sample_commit(sha: "abcdef1234567890", message: "feat: add dark mode toggle"),
        sample_commit(sha: "1234567890abcdef", message: "fix: resolved login crash")
      ])
      allow(mock_response).to receive(:body).and_return(body)

      result = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!

      expect(result).to include("- abcdef1 feat: add dark mode toggle")
      expect(result).to include("- 1234567 fix: resolved login crash")
    end

    it "takes only the first line of multi-line commit messages" do
      body = build_body([
        sample_commit(sha: "abcdef1", message: "feat: add dark mode\n\nDetailed body here\nMore details")
      ])
      allow(mock_response).to receive(:body).and_return(body)

      result = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!

      expect(result).to eq("- abcdef1 feat: add dark mode")
    end

    it "skips commits with blank messages" do
      body = build_body([
        sample_commit(sha: "abcdef1", message: ""),
        sample_commit(sha: "1234567", message: "feat: valid commit")
      ])
      allow(mock_response).to receive(:body).and_return(body)

      result = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!

      expect(result).to eq("- 1234567 feat: valid commit")
    end

    it "returns empty string when commits array is empty" do
      allow(mock_response).to receive(:body).and_return(build_body([]))

      result = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!

      expect(result).to eq("")
    end

    it "returns empty string when commits key is missing" do
      allow(mock_response).to receive(:body).and_return("{}")

      result = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!

      expect(result).to eq("")
    end

    it "respects MAX_COMMITS limit" do
      many_commits = Array.new(150) do |i|
        sample_commit(sha: "sha#{i.to_s.rjust(4, '0')}", message: "commit #{i}")
      end
      allow(mock_response).to receive(:body).and_return(build_body(many_commits))

      result = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!

      lines = result.lines
      expect(lines.size).to eq(described_class::MAX_COMMITS)
    end

    it "escapes refs for URL safety" do
      allow(mock_response).to receive(:body).and_return(build_body([]))

      described_class.new(repo_url: repo_url, from_ref: "feature/foo", to_ref: "main").fetch!

      expect(mock_connection).to have_received(:get).with(/feature%2Ffoo/)
    end
  end

  describe "error handling" do
    before do
      allow(mock_connection).to receive(:get).and_return(mock_response)
    end

    it "raises FetchError on 404 response" do
      allow(mock_response).to receive(:success?).and_return(false)
      allow(mock_response).to receive(:status).and_return(404)
      allow(mock_response).to receive(:body).and_return({ "message" => "Not Found" }.to_json)

      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::FetchError, /Not Found/)
    end

    it "raises FetchError on 422 response with message" do
      allow(mock_response).to receive(:success?).and_return(false)
      allow(mock_response).to receive(:status).and_return(422)
      allow(mock_response).to receive(:body).and_return({ "message" => "No common ancestor" }.to_json)

      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::FetchError, /No common ancestor/)
    end

    it "raises FetchError with HTTP status when no message in body" do
      allow(mock_response).to receive(:success?).and_return(false)
      allow(mock_response).to receive(:status).and_return(500)
      allow(mock_response).to receive(:body).and_return("")

      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::FetchError, /HTTP 500/)
    end

    it "raises FetchError on network error" do
      allow(mock_connection).to receive(:get).and_raise(Faraday::ConnectionFailed.new("connection refused"))

      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::FetchError, /Network error/)
    end

    it "raises FetchError on timeout" do
      allow(mock_connection).to receive(:get).and_raise(Faraday::TimeoutError.new("timeout"))

      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::FetchError, /Network error/)
    end

    it "handles non-JSON error body gracefully" do
      allow(mock_response).to receive(:success?).and_return(false)
      allow(mock_response).to receive(:status).and_return(500)
      allow(mock_response).to receive(:body).and_return("Internal Server Error")

      fetcher = described_class.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref)
      expect { fetcher.fetch! }.to raise_error(ReleaseNotes::GitLogFetcher::FetchError, /HTTP 500/)
    end
  end
end
