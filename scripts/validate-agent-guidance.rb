#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SKILLS_DIR = File.join(ROOT, ".agents", "skills")
RULES_DIR = File.join(ROOT, ".agents", "rules")
DOC_MAP = File.join(ROOT, ".agents", "references", "red-hat-doc-map.yaml")
AGENT_GUIDANCE = File.join(ROOT, ".agents", "skills", "project-agent-guidance", "SKILL.md")

ALLOWED_SKILL_GROUPS = Set[
  "Project Structure",
  "Demo Environment",
  "RHOAI Platform",
  "OpenShift Platform",
  "OpenShift Data Foundation",
  "Assets & Miscellaneous"
].freeze

ALLOWED_ROUTE_STATUSES = Set[
  "active",
  "planned",
  "blocked-baseline"
].freeze

ALLOWED_SOURCE_TYPES = Set[
  "docs_redhat_com",
  "customer_portal_article",
  "external_redhat_product_docs",
  "repo_specific"
].freeze

NONCANONICAL_RHOAI_BOOK_SLUGS = {
  "installing_and_uninstalling_openshift_ai_self_managed" =>
    "installing_and_uninstalling_openshift_ai_self-managed",
  "configuring_your_model_serving_platform" =>
    "configuring_your_model-serving_platform",
  "working_with_data_in_an_s3_compatible_object_store" =>
    "working_with_data_in_an_s3-compatible_object_store",
  "govern_llm_access_with_models_as_a_service" =>
    "govern_llm_access_with_models-as-a-service",
  "deploy_models_using_distributed_inference_with_llm_d" =>
    "deploy_models_using_distributed_inference_with_llm-d"
}.freeze

@errors = []
@warnings = []

def rel(path)
  path.sub("#{ROOT}/", "")
end

def error(message)
  @errors << message
end

def warn_check(message)
  @warnings << message
end

def frontmatter(path)
  text = File.read(path)
  unless text.start_with?("---\n")
    error("#{rel(path)} is missing YAML frontmatter")
    return [{}, text]
  end

  parts = text.split(/^---\s*$/, 3)
  if parts.length < 3
    error("#{rel(path)} has malformed YAML frontmatter")
    return [{}, text]
  end

  [YAML.safe_load(parts[1], permitted_classes: [Symbol], aliases: true) || {}, text]
rescue Psych::SyntaxError => e
  error("#{rel(path)} has invalid YAML frontmatter: #{e.message}")
  [{}, File.read(path)]
end

def skill_files
  Dir[File.join(SKILLS_DIR, "*", "SKILL.md")].sort
end

def validate_skills
  skills = {}

  skill_files.each do |path|
    metadata, = frontmatter(path)
    dir_name = File.basename(File.dirname(path))
    skill_name = metadata["name"]
    skills[dir_name] = path

    error("#{rel(path)} frontmatter name #{skill_name.inspect} does not match folder #{dir_name.inspect}") unless skill_name == dir_name

    required = %w[version platform-family platform-baseline ocp-baseline skill-group]
    missing = required.reject { |key| metadata.dig("metadata", key) }
    error("#{rel(path)} metadata is missing #{missing.join(', ')}") unless missing.empty?

    group = metadata.dig("metadata", "skill-group")
    error("#{rel(path)} has unknown skill group #{group.inspect}") if group && !ALLOWED_SKILL_GROUPS.include?(group)
  end

  skills
end

def validate_rules(skills)
  Dir[File.join(RULES_DIR, "*.md")].sort.each do |path|
    next if File.basename(path) == "README.md"

    metadata, text = frontmatter(path)
    error("#{rel(path)} frontmatter name #{metadata['name'].inspect} should match filename") unless metadata["name"] == File.basename(path, ".md")

    prefix = metadata["skill-prefix"]
    if prefix
      expected = skills.keys.select { |name| name.start_with?(prefix) }.sort
      referenced = text.scan(%r{\.agents/skills/([^/\s`]+)/SKILL\.md}).flatten.uniq.sort
      missing = expected - referenced
      error("#{rel(path)} does not reference #{missing.join(', ')}") unless missing.empty?
    end

    text.scan(%r{\.agents/skills/([^/\s`]+)/SKILL\.md}).flatten.each do |skill|
      next if skill.include?("*") || skill.include?("<") || skill.include?(">")

      error("#{rel(path)} references missing skill #{skill}") unless skills.key?(skill)
    end
  end
end

def walk_routes(node, path = [], &block)
  case node
  when Hash
    yield node, path if node.key?("status") && node.key?("skill")
    node.each { |key, value| walk_routes(value, path + [key.to_s], &block) }
  when Array
    node.each_with_index { |value, index| walk_routes(value, path + [index.to_s], &block) }
  end
end

def validate_doc_map(skills)
  map = YAML.load_file(DOC_MAP)
  statuses = Hash.new(0)
  planned = []

  purpose = map["purpose"].to_s
  if purpose.include?("models the Red Hat documentation hierarchy")
    error("#{rel(DOC_MAP)} purpose still overclaims exact documentation hierarchy modeling")
  end

  walk_routes(map) do |route, path|
    status = route["status"]
    skill = route["skill"]
    book = route["book"].to_s
    source_type = route["source_type"]

    statuses[status] += 1
    error("#{rel(DOC_MAP)} route #{path.join('/')} has unsupported status #{status.inspect}") unless ALLOWED_ROUTE_STATUSES.include?(status)

    if source_type && !ALLOWED_SOURCE_TYPES.include?(source_type)
      error("#{rel(DOC_MAP)} route #{path.join('/')} has unsupported source_type #{source_type.inspect}")
    end

    if status == "active" && !skills.key?(skill)
      error("#{rel(DOC_MAP)} active route #{path.join('/')} points to missing skill #{skill}")
    elsif status == "planned"
      planned << skill
      if skills.key?(skill)
        error("#{rel(DOC_MAP)} planned route #{path.join('/')} points to existing skill #{skill}; set status active")
      end
    end

    if NONCANONICAL_RHOAI_BOOK_SLUGS.key?(book)
      error("#{rel(DOC_MAP)} route #{path.join('/')} uses noncanonical book #{book}; use #{NONCANONICAL_RHOAI_BOOK_SLUGS[book]}")
    end

    if source_type == "customer_portal_article" && route["source_url"].to_s.empty?
      error("#{rel(DOC_MAP)} route #{path.join('/')} has customer_portal_article without source_url")
    end
  end

  [statuses, planned.sort.uniq]
rescue Psych::SyntaxError => e
  error("#{rel(DOC_MAP)} is not valid YAML: #{e.message}")
  [{}, []]
end

def validate_guidance_inventory(skill_count)
  text = File.read(AGENT_GUIDANCE)
  match = text.match(/\| Shared skills \| (?<count>\d+) \|/)
  if match
    expected = match[:count].to_i
    error("#{rel(AGENT_GUIDANCE)} shared skill count is #{expected}, expected #{skill_count}") unless expected == skill_count
  else
    error("#{rel(AGENT_GUIDANCE)} does not contain shared skill count row")
  end
end

def validate_referenced_skill_paths(skills)
  files = Dir[
    File.join(ROOT, "AGENTS.md"),
    File.join(ROOT, ".agents", "rules", "*.md"),
    File.join(ROOT, ".agents", "skills", "project-structure", "SKILL.md"),
    File.join(ROOT, ".agents", "skills", "project-agent-guidance", "SKILL.md")
  ]

  files.each do |path|
    text = File.read(path)
    text.scan(%r{\.agents/skills/([^/\s`]+)/SKILL\.md}).flatten.each do |skill|
      next if skill.include?("*") || skill.include?("<") || skill.include?(">")

      error("#{rel(path)} references missing skill #{skill}") unless skills.key?(skill)
    end
  end
end

skills = validate_skills
validate_rules(skills)
validate_referenced_skill_paths(skills)
statuses, planned = validate_doc_map(skills)
validate_guidance_inventory(skills.length)

puts "Agent guidance validation"
puts "  skills: #{skills.length}"
puts "  route statuses: #{statuses.sort.map { |status, count| "#{status}=#{count}" }.join(', ')}"
puts "  planned routes: #{planned.empty? ? 'none' : planned.join(', ')}"

unless @warnings.empty?
  puts "\nWarnings:"
  @warnings.each { |message| puts "  - #{message}" }
end

if @errors.empty?
  puts "  result: ok"
else
  puts "\nErrors:"
  @errors.each { |message| puts "  - #{message}" }
  exit 1
end
