# Decides the weekly release. The next patch version is released only when every commit since the latest vX.Y.Z tag,
# merge commits aside, is Renovate's, and they changed something outside .github/ and renovate.json. Anything else is
# left to a release by hand.
#
# Run as a script, it prints the reason, and in GitHub Actions writes version and message to $GITHUB_OUTPUT; version
# is empty when nothing is released.
require "open3"
require "securerandom"

module ReleasePlan
  RENOVATE = "renovate[bot]"

  Commit = Struct.new(:author, :subject)
  Plan = Struct.new(:version, :message, :reason, keyword_init: true)

  VERSION_TAG = /\Av(\d+)\.(\d+)\.(\d+)\z/

  def self.latest_version_tag(tags)
    tags.select { |tag| VERSION_TAG.match?(tag) }.max_by { |tag| VERSION_TAG.match(tag).captures.map(&:to_i) }
  end

  # Changes to these alone do not reach the image: .dockerignore leaves .github/ out of it, and renovate.json is only
  # read by Renovate.
  def self.outside_release?(path)
    path.start_with?(".github/") || path == "renovate.json"
  end

  def self.decide(tag, commits, changed)
    return Plan.new(reason: "no commits other than merges since #{tag}; nothing to release") if commits.empty?

    others = commits.map(&:author).reject { |author| author == RENOVATE }.uniq
    unless others.empty?
      return Plan.new(reason: "commits since #{tag} by #{others.join(", ")}, not only #{RENOVATE}; releasing them is left to a person")
    end

    changed = changed.reject { |path| outside_release?(path) }
    if changed.empty?
      return Plan.new(reason: "#{RENOVATE}'s commits since #{tag} change only .github/ and renovate.json; nothing to release")
    end

    major, minor, patch = VERSION_TAG.match(tag).captures.map(&:to_i)
    version = "v#{major}.#{minor}.#{patch + 1}"
    message = [
      "#{version}: dependency updates",
      "",
      "Only Renovate's dependency updates since #{tag}, released by the weekly workflow:",
      "",
      *commits.map { |c| "- #{c.subject}" }
    ].join("\n")
    Plan.new(
      version: version,
      message: message,
      reason: "only #{RENOVATE}'s commits since #{tag}, changing #{changed.join(", ")}; releasing #{version}"
    )
  end

  def self.from_git(dir)
    git = lambda do |*args|
      out, status = Open3.capture2("git", *args, chdir: dir)
      raise "git #{args.join(" ")} failed" unless status.success?
      out.lines(chomp: true).reject(&:empty?)
    end

    tag = latest_version_tag(git.call("tag", "--list", "--merged", "HEAD"))
    return Plan.new(reason: "no vX.Y.Z tag reachable from HEAD; the first version is a person's to choose") unless tag

    commits = git.call("log", "--no-merges", "--reverse", "--format=%an%x1f%s", "#{tag}..HEAD").map do |line|
      Commit.new(*line.split("\x1f", 2))
    end
    decide(tag, commits, git.call("diff", "--name-only", tag, "HEAD"))
  end
end

if $PROGRAM_NAME == __FILE__
  plan = ReleasePlan.from_git(Dir.pwd)
  puts plan.reason
  if (output = ENV["GITHUB_OUTPUT"])
    delimiter = "EOF_#{SecureRandom.hex(16)}"
    File.write(output, "version=#{plan.version}\nmessage<<#{delimiter}\n#{plan.message}\n#{delimiter}\n", mode: "a")
  end
end
