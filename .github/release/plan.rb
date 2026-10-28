# Decides an automatic release. The next patch version is released only when every commit since the latest vX.Y.Z
# tag, merge commits aside, is Renovate's or fraction-vuln-responder's, and they changed something outside .github/ and
# renovate.json. Anything else is left to a release by hand.
#
# Run as a script, it prints the reason, and in GitHub Actions writes version and message to $GITHUB_OUTPUT and the
# reason to $GITHUB_STEP_SUMMARY, with the commits that held the release and how to release them by hand; version is
# empty when nothing is released. $RELEASED_BY says what released it in the tag's message (the weekly workflow by
# default).
require "open3"
require "securerandom"

module ReleasePlan
  RENOVATE = "renovate[bot]"
  # The GitHub App of the vulnerability responder (fraction-agents), which opens fixes from vuln-responder/ branches.
  VULN_RESPONDER = "fraction-vuln-responder[bot]"
  BOTS = [RENOVATE, VULN_RESPONDER].freeze

  Commit = Struct.new(:author, :subject, :sha)
  Plan = Struct.new(:version, :message, :reason, :held, :next_version, :head, keyword_init: true)

  VERSION_TAG = /\Av(\d+)\.(\d+)\.(\d+)\z/

  def self.latest_version_tag(tags)
    tags.select { |tag| VERSION_TAG.match?(tag) }.max_by { |tag| VERSION_TAG.match(tag).captures.map(&:to_i) }
  end

  # Changes to these alone do not reach the image: .dockerignore leaves .github/ out of it, and renovate.json is only
  # read by Renovate.
  def self.outside_release?(path)
    path.start_with?(".github/") || path == "renovate.json"
  end

  def self.decide(tag, commits, changed, released_by: "the weekly workflow", head: nil)
    return Plan.new(reason: "no commits other than merges since #{tag}; nothing to release", held: []) if commits.empty?

    major, minor, patch = VERSION_TAG.match(tag).captures.map(&:to_i)
    version = "v#{major}.#{minor}.#{patch + 1}"

    held = commits.reject { |c| BOTS.include?(c.author) }
    unless held.empty?
      return Plan.new(
        reason: "commits since #{tag} by #{held.map(&:author).uniq.join(", ")}, not only #{BOTS.join(" and ")}; " \
                "releasing them is left to a person",
        held: held, next_version: version, head: head
      )
    end

    changed = changed.reject { |path| outside_release?(path) }
    if changed.empty?
      return Plan.new(reason: "the commits since #{tag} change only .github/ and renovate.json; nothing to release", held: [])
    end

    authors = commits.map(&:author)
    fixes = authors.include?(VULN_RESPONDER)
    updates = authors.include?(RENOVATE)
    title, only =
      if fixes && updates
        ["vulnerability fixes and dependency updates", "#{VULN_RESPONDER}'s fixes and Renovate's dependency updates"]
      elsif fixes
        ["vulnerability fixes", "#{VULN_RESPONDER}'s fixes"]
      else
        ["dependency updates", "Renovate's dependency updates"]
      end
    message = [
      "#{version}: #{title}",
      "",
      "Only #{only} since #{tag}, released by #{released_by}:",
      "",
      *commits.map { |c| "- #{c.subject}" }
    ].join("\n")
    Plan.new(
      version: version,
      message: message,
      reason: "only #{authors.uniq.join(" and ")}'s commits since #{tag}, changing #{changed.join(", ")}; releasing #{version}",
      held: []
    )
  end

  # Markdown for the job summary: the reason, and when commits held the release, them and the commands that release
  # the same commit by hand. A tag pushed by hand publishes the image through image.yaml.
  def self.summary(plan)
    lines = ["## Release", "", plan.reason]
    return lines.join("\n") + "\n" if plan.held.nil? || plan.held.empty?

    lines += [
      "",
      "### Commits that held the release",
      "",
      *plan.held.map { |c| "- #{c.sha.to_s[0, 7]} #{c.subject} (#{c.author})" },
      "",
      "### Releasing by hand",
      "",
      "Once they are fit to release, tag the commit this run looked at (or choose another version):",
      "",
      "```sh",
      "git fetch origin --tags",
      "git tag --annotate --message=#{plan.next_version} #{plan.next_version} #{plan.head}",
      "git push origin #{plan.next_version}",
      "```"
    ]
    lines.join("\n") + "\n"
  end

  def self.from_git(dir, released_by: "the weekly workflow")
    git = lambda do |*args|
      out, status = Open3.capture2("git", *args, chdir: dir)
      raise "git #{args.join(" ")} failed" unless status.success?
      out.lines(chomp: true).reject(&:empty?)
    end

    tag = latest_version_tag(git.call("tag", "--list", "--merged", "HEAD"))
    return Plan.new(reason: "no vX.Y.Z tag reachable from HEAD; the first version is a person's to choose", held: []) unless tag

    commits = git.call("log", "--no-merges", "--reverse", "--format=%an%x1f%H%x1f%s", "#{tag}..HEAD").map do |line|
      author, sha, subject = line.split("\x1f", 3)
      Commit.new(author, subject, sha)
    end
    decide(tag, commits, git.call("diff", "--name-only", tag, "HEAD"),
           released_by: released_by, head: git.call("rev-parse", "HEAD").first)
  end
end

if $PROGRAM_NAME == __FILE__
  released_by = ENV["RELEASED_BY"].to_s.empty? ? "the weekly workflow" : ENV["RELEASED_BY"]
  plan = ReleasePlan.from_git(Dir.pwd, released_by: released_by)
  puts plan.reason
  if (output = ENV["GITHUB_OUTPUT"])
    delimiter = "EOF_#{SecureRandom.hex(16)}"
    File.write(output, "version=#{plan.version}\nmessage<<#{delimiter}\n#{plan.message}\n#{delimiter}\n", mode: "a")
  end
  if (summary = ENV["GITHUB_STEP_SUMMARY"])
    File.write(summary, ReleasePlan.summary(plan), mode: "a")
  end
end
