# Run with: ruby .github/release/plan_test.rb
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "plan"

class LatestVersionTagTest < Minitest::Test
  def test_compares_versions_as_numbers
    assert_equal "v0.10.0", ReleasePlan.latest_version_tag(%w[v0.9.1 v0.10.0 v0.2.0])
  end

  def test_skips_tags_that_are_not_vX_Y_Z
    assert_equal "v0.4.0", ReleasePlan.latest_version_tag(%w[v0.4.0 v0.5.0-rc1 v0.17.0.1 0.6.0 latest])
  end

  def test_nothing_without_a_version_tag
    assert_nil ReleasePlan.latest_version_tag(%w[latest 1.0])
  end
end

class DecideTest < Minitest::Test
  RENOVATE = ReleasePlan::RENOVATE

  def commit(author, subject)
    ReleasePlan::Commit.new(author, subject)
  end

  def test_releases_the_next_patch_when_every_commit_is_renovates
    plan = ReleasePlan.decide(
      "v0.4.0",
      [commit(RENOVATE, "chore(deps): update ruby docker tag to v4.0.10"), commit(RENOVATE, "chore(deps): update dependency json to v2.19.0")],
      %w[Dockerfile Gemfile.lock]
    )
    assert_equal "v0.4.1", plan.version
    assert_equal <<~MESSAGE.chomp, plan.message
      v0.4.1: dependency updates

      Only Renovate's dependency updates since v0.4.0, released by the weekly workflow:

      - chore(deps): update ruby docker tag to v4.0.10
      - chore(deps): update dependency json to v2.19.0
    MESSAGE
    assert_match "Dockerfile", plan.reason
  end

  def test_leaves_a_persons_commit_to_a_person
    plan = ReleasePlan.decide(
      "v0.4.0",
      [commit(RENOVATE, "chore(deps): update dependency json to v2.19.0"), commit("OTSUKA, Yuanying", "Support audio posts")],
      %w[Gemfile.lock download.rb]
    )
    assert_nil plan.version
    assert_nil plan.message
    assert_match "OTSUKA, Yuanying", plan.reason
  end

  def test_nothing_since_the_tag
    plan = ReleasePlan.decide("v0.4.0", [], [])
    assert_nil plan.version
    assert_match "v0.4.0", plan.reason
  end

  def test_workflows_and_renovate_json_alone_are_not_released
    plan = ReleasePlan.decide(
      "v0.4.0",
      [commit(RENOVATE, "chore(deps): update github-actions")],
      %w[.github/workflows/image.yaml renovate.json]
    )
    assert_nil plan.version
  end
end

class FromGitTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    git "init", "--quiet", "--initial-branch=master"
    commit_as "OTSUKA, Yuanying", "Dockerfile", "First"
    git "tag", "--annotate", "--message=v0.4.0", "v0.4.0"
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def git(*args, author: "OTSUKA, Yuanying")
    env = {
      "GIT_AUTHOR_NAME" => author, "GIT_AUTHOR_EMAIL" => "a@example.com",
      "GIT_COMMITTER_NAME" => author, "GIT_COMMITTER_EMAIL" => "a@example.com",
      "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1"
    }
    out, status = Open3.capture2e(env, "git", *args, chdir: @dir)
    raise out unless status.success?
    out
  end

  def commit_as(author, path, subject)
    File.write(File.join(@dir, path), subject)
    git "add", path
    git "commit", "--quiet", "--message=#{subject}", author: author
  end

  def test_releases_renovates_commits_merged_into_master
    git "checkout", "--quiet", "-b", "renovate/json"
    commit_as ReleasePlan::RENOVATE, "Gemfile.lock", "chore(deps): update dependency json to v2.19.0"
    git "checkout", "--quiet", "master"
    git "merge", "--quiet", "--no-ff", "--message=Merge pull request #20", "renovate/json"

    plan = ReleasePlan.from_git(@dir)
    assert_equal "v0.4.1", plan.version
    assert_includes plan.message, "- chore(deps): update dependency json to v2.19.0"
    refute_includes plan.message, "Merge pull request"
  end

  def test_a_persons_commit_since_the_tag_holds_the_release
    commit_as ReleasePlan::RENOVATE, "Gemfile.lock", "chore(deps): update dependency json to v2.19.0"
    commit_as "OTSUKA, Yuanying", "download.rb", "Support audio posts"

    assert_nil ReleasePlan.from_git(@dir).version
  end

  def test_ignores_a_version_tag_not_reachable_from_head
    git "checkout", "--quiet", "-b", "elsewhere"
    commit_as "OTSUKA, Yuanying", "download.rb", "Elsewhere"
    git "tag", "v9.0.0"
    git "checkout", "--quiet", "master"
    commit_as ReleasePlan::RENOVATE, "Gemfile.lock", "chore(deps): update dependency json to v2.19.0"

    assert_equal "v0.4.1", ReleasePlan.from_git(@dir).version
  end

  def test_no_version_tag_is_no_release
    git "tag", "--delete", "v0.4.0"
    assert_nil ReleasePlan.from_git(@dir).version
  end
end
