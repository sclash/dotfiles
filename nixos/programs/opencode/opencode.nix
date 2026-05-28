{
  config,
  lib,
  pkgs,
  pkgs-master,
  ...
}:
{
  programs.opencode = {
    enable = true;
    package = pkgs-master.opencode;
    # enableMcpIntegration = true;
    # settings = {
    #   provider = {
    #     "llama.cpp" = {
    #       npm = "@ai-sdk/openai-compatible";
    #       name = "llama-server (vast.ai)";
    #       options = {
    #         baseURL = "http://202.214.223.66:26282/";
    #       };
    #       models = {
    #         "unsloth/Qwen3.6-27B-GGUF" = {
    #           name = "Qwen3.6-27B";
    #         };
    #       };
    #     };
    #     "vast.ai-RTX4080S" = {
    #       npm = "@ai-sdk/openai-compatible";
    #       name = "llama-server (vast.ai)";
    #       options = {
    #         baseURL = "http://175.155.64.149:20073/";
    #       };
    #       models = {
    #         "unsloth/Qwen3.6-35B-A3B-GGUF" = {
    #           name = "Qwen3.6-35B-A3B";
    #         };
    #       };
    #     };
    #     "vast.ai-RTXPRO4500" = {
    #       npm = "@ai-sdk/openai-compatible";
    #       name = "llama-server (vast.ai)";
    #       options = {
    #         baseURL = "http://74.15.83.230:50573/";
    #       };
    #       models = {
    #         "unsloth/Qwen3.6-35B-A3B-GGUF" = {
    #           name = "RTX4500-Qwen3.6-35B-A3B";
    #         };
    #       };
    #     };
    #   };
    #
    #   lsp = {
    #     zig = {
    #       command = [ "zls" ];
    #       extensions = [
    #         ".zig"
    #         ".zon"
    #       ];
    #     };
    #     tailwind = {
    #       command = [
    #         "npx"
    #         "-p"
    #         "@tailwindcss/language-server"
    #         "-y"
    #         "tailwindcss-language-server"
    #         "--stdio"
    #       ];
    #       extensions = [
    #         ".css"
    #         ".htmx"
    #         ".vue"
    #         ".jsx"
    #         ".tsx"
    #       ];
    #     };
    #   };
    #
    #   plugin = [
    #     "superpowers@git+https://github.com/obra/superpowers.git"
    #     "context-mode"
    #     "ecc-universal"
    #     "claude-mem"
    #   ];
    #
    #   instructions = [
    #     "AGENTS.md"
    #     "instructions/INSTRUCTIONS.md"
    #     # "skills/tdd-workflow/SKILL.md"
    #     # "skills/security-review/SKILL.md"
    #     # "skills/coding-standards/SKILL.md"
    #     # "skills/frontend-patterns/SKILL.md"
    #     # "skills/frontend-slides/SKILL.md"
    #     # "skills/backend-patterns/SKILL.md"
    #     # "skills/e2e-testing/SKILL.md"
    #     # "skills/verification-loop/SKILL.md"
    #     # "skills/api-design/SKILL.md"
    #     # "skills/strategic-compact/SKILL.md"
    #     # "skills/eval-harness/SKILL.md"
    #   ];
    #
    #   agent = {
    #     build = {
    #       description = "Primary coding agent for development work";
    #       mode = "primary";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       tools = {
    #         write = true;
    #         edit = true;
    #         bash = true;
    #         read = true;
    #         changed-files = true;
    #       };
    #     };
    #     planner = {
    #       description = "Expert planning specialist for complex features and refactoring. Use for implementation planning, architectural changes, or complex refactoring.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/planner.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     architect = {
    #       description = "Software architecture specialist for system design, scalability, and technical decision-making.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/architect.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "code-reviewer" = {
    #       description = "Expert code review specialist. Reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/code-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "security-reviewer" = {
    #       description = "Security vulnerability detection and remediation specialist. Use after writing code that handles user input, authentication, API endpoints, or sensitive data.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/security-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = true;
    #         edit = true;
    #       };
    #     };
    #     "tdd-guide" = {
    #       description = "Test-Driven Development specialist enforcing write-tests-first methodology. Use when writing new features, fixing bugs, or refactoring code. Ensures 80%+ test coverage.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/tdd-guide.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "build-error-resolver" = {
    #       description = "Build and TypeScript error resolution specialist. Use when build fails or type errors occur. Fixes build/type errors only with minimal diffs.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/build-error-resolver.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "e2e-runner" = {
    #       description = "End-to-end testing specialist using Playwright. Generates, maintains, and runs E2E tests for critical user flows.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/e2e-runner.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "doc-updater" = {
    #       description = "Documentation and codemap specialist. Use for updating codemaps and documentation.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/doc-updater.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "refactor-cleaner" = {
    #       description = "Dead code cleanup and consolidation specialist. Use for removing unused code, duplicates, and refactoring.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/refactor-cleaner.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "go-reviewer" = {
    #       description = "Expert Go code reviewer specializing in idiomatic Go, concurrency patterns, error handling, and performance.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/go-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "go-build-resolver" = {
    #       description = "Go build, vet, and compilation error resolution specialist. Fixes Go build errors with minimal changes.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/go-build-resolver.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "database-reviewer" = {
    #       description = "PostgreSQL database specialist for query optimization, schema design, security, and performance. Incorporates Supabase best practices.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/database-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "cpp-reviewer" = {
    #       description = "Expert C++ code reviewer specializing in memory safety, modern C++ idioms, concurrency, and performance. Use for all C++ code changes.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/cpp-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "cpp-build-resolver" = {
    #       description = "C++ build, CMake, and compilation error resolution specialist. Fixes build errors, linker issues, and template errors with minimal changes.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/cpp-build-resolver.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "docs-lookup" = {
    #       description = "Documentation specialist using Context7 MCP to fetch current library and API documentation with code examples.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/docs-lookup.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "harness-optimizer" = {
    #       description = "Analyze and improve the local agent harness configuration for reliability, cost, and throughput.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/harness-optimizer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         edit = true;
    #       };
    #     };
    #     "java-reviewer" = {
    #       description = "Expert Java and Spring Boot code reviewer specializing in layered architecture, JPA patterns, security, and concurrency.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/java-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "java-build-resolver" = {
    #       description = "Java/Maven/Gradle build, compilation, and dependency error resolution specialist. Fixes build errors with minimal changes.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/java-build-resolver.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "kotlin-reviewer" = {
    #       description = "Kotlin and Android/KMP code reviewer. Reviews Kotlin code for idiomatic patterns, coroutine safety, Compose best practices.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/kotlin-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "kotlin-build-resolver" = {
    #       description = "Kotlin/Gradle build, compilation, and dependency error resolution specialist. Fixes Kotlin build errors with minimal changes.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/kotlin-build-resolver.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #     "loop-operator" = {
    #       description = "Operate autonomous agent loops, monitor progress, and intervene safely when loops stall.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/loop-operator.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         edit = true;
    #       };
    #     };
    #     "python-reviewer" = {
    #       description = "Expert Python code reviewer specializing in PEP 8 compliance, Pythonic idioms, type hints, security, and performance.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/python-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "rust-reviewer" = {
    #       description = "Expert Rust code reviewer specializing in idiomatic Rust, ownership, lifetimes, concurrency, and performance.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/rust-reviewer.txt}";
    #       tools = {
    #         read = true;
    #         bash = true;
    #         write = false;
    #         edit = false;
    #       };
    #     };
    #     "rust-build-resolver" = {
    #       description = "Rust build, Cargo, and compilation error resolution specialist. Fixes Rust build errors with minimal changes.";
    #       mode = "subagent";
    #       model = "llama.cpp/unsloth/Qwen3.6-27B-GGUF";
    #       prompt = "{file:prompts/agents/rust-build-resolver.txt}";
    #       tools = {
    #         read = true;
    #         write = true;
    #         edit = true;
    #         bash = true;
    #       };
    #     };
    #   };
    #
    #   command = {
    #     plan = {
    #       description = "Create a detailed implementation plan for complex features";
    #       template = "{file:commands/plan.md}\n\n$ARGUMENTS";
    #       agent = "planner";
    #       subtask = true;
    #     };
    #     tdd = {
    #       description = "Enforce TDD workflow with 80%+ test coverage";
    #       template = "{file:commands/tdd.md}\n\n$ARGUMENTS";
    #       agent = "tdd-guide";
    #       subtask = true;
    #     };
    #     "code-review" = {
    #       description = "Review code for quality, security, and maintainability";
    #       template = "{file:commands/code-review.md}\n\n$ARGUMENTS";
    #       agent = "code-reviewer";
    #       subtask = true;
    #     };
    #     security = {
    #       description = "Run comprehensive security review";
    #       template = "{file:commands/security.md}\n\n$ARGUMENTS";
    #       agent = "security-reviewer";
    #       subtask = true;
    #     };
    #     "build-fix" = {
    #       description = "Fix build and TypeScript errors with minimal changes";
    #       template = "{file:commands/build-fix.md}\n\n$ARGUMENTS";
    #       agent = "build-error-resolver";
    #       subtask = true;
    #     };
    #     e2e = {
    #       description = "Generate and run E2E tests with Playwright";
    #       template = "{file:commands/e2e.md}\n\n$ARGUMENTS";
    #       agent = "e2e-runner";
    #       subtask = true;
    #     };
    #     "refactor-clean" = {
    #       description = "Remove dead code and consolidate duplicates";
    #       template = "{file:commands/refactor-clean.md}\n\n$ARGUMENTS";
    #       agent = "refactor-cleaner";
    #       subtask = true;
    #     };
    #     orchestrate = {
    #       description = "Orchestrate multiple agents for complex tasks";
    #       template = "{file:commands/orchestrate.md}\n\n$ARGUMENTS";
    #       agent = "planner";
    #       subtask = true;
    #     };
    #     learn = {
    #       description = "Extract patterns and learnings from session";
    #       template = "{file:commands/learn.md}\n\n$ARGUMENTS";
    #     };
    #     checkpoint = {
    #       description = "Save verification state and progress";
    #       template = "{file:commands/checkpoint.md}\n\n$ARGUMENTS";
    #     };
    #     verify = {
    #       description = "Run verification loop";
    #       template = "{file:commands/verify.md}\n\n$ARGUMENTS";
    #     };
    #     eval = {
    #       description = "Run evaluation against criteria";
    #       template = "{file:commands/eval.md}\n\n$ARGUMENTS";
    #     };
    #     "update-docs" = {
    #       description = "Update documentation";
    #       template = "{file:commands/update-docs.md}\n\n$ARGUMENTS";
    #       agent = "doc-updater";
    #       subtask = true;
    #     };
    #     "update-codemaps" = {
    #       description = "Update codemaps";
    #       template = "{file:commands/update-codemaps.md}\n\n$ARGUMENTS";
    #       agent = "doc-updater";
    #       subtask = true;
    #     };
    #     "test-coverage" = {
    #       description = "Analyze test coverage";
    #       template = "{file:commands/test-coverage.md}\n\n$ARGUMENTS";
    #       agent = "tdd-guide";
    #       subtask = true;
    #     };
    #     "setup-pm" = {
    #       description = "Configure package manager";
    #       template = "{file:commands/setup-pm.md}\n\n$ARGUMENTS";
    #     };
    #     "go-review" = {
    #       description = "Go code review";
    #       template = "{file:commands/go-review.md}\n\n$ARGUMENTS";
    #       agent = "go-reviewer";
    #       subtask = true;
    #     };
    #     "go-test" = {
    #       description = "Go TDD workflow";
    #       template = "{file:commands/go-test.md}\n\n$ARGUMENTS";
    #       agent = "tdd-guide";
    #       subtask = true;
    #     };
    #     "go-build" = {
    #       description = "Fix Go build errors";
    #       template = "{file:commands/go-build.md}\n\n$ARGUMENTS";
    #       agent = "go-build-resolver";
    #       subtask = true;
    #     };
    #     "skill-create" = {
    #       description = "Generate skills from git history";
    #       template = "{file:commands/skill-create.md}\n\n$ARGUMENTS";
    #     };
    #     "instinct-status" = {
    #       description = "View learned instincts";
    #       template = "{file:commands/instinct-status.md}\n\n$ARGUMENTS";
    #     };
    #     "instinct-import" = {
    #       description = "Import instincts";
    #       template = "{file:commands/instinct-import.md}\n\n$ARGUMENTS";
    #     };
    #     "instinct-export" = {
    #       description = "Export instincts";
    #       template = "{file:commands/instinct-export.md}\n\n$ARGUMENTS";
    #     };
    #     evolve = {
    #       description = "Cluster instincts into skills";
    #       template = "{file:commands/evolve.md}\n\n$ARGUMENTS";
    #     };
    #     promote = {
    #       description = "Promote project instincts to global scope";
    #       template = "{file:commands/promote.md}\n\n$ARGUMENTS";
    #     };
    #     projects = {
    #       description = "List known projects and instinct stats";
    #       template = "{file:commands/projects.md}\n\n$ARGUMENTS";
    #     };
    #   };
    #
    #   permission = {
    #     "mcp_*" = "ask";
    #   };
    # };
  };

  # Symlink dotfiles opencode content dirs into ~/.config/opencode/
  # so that {file:prompts/...}, {file:commands/...}, and instructions
  # resolve correctly relative to the config directory.
  home.file = {
    ".config/opencode/opencode.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/opencode/opencode.json";
      force = true;
    };
    # ".config/opencode/agents" = {
    #   source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/agents";
    #   force = true;
    #   # recursive = true;
    # };
    ".config/opencode/prompts" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/prompts";
      force = true;
      # recursive = true;
    };
    ".config/opencode/commands" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/commands";
      force = true;
      # recursive = true;
    };
    ".config/opencode/instructions" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/instructions";
      force = true;
      # recursive = true;
    };
    ".config/opencode/skills" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/skills";
      force = true;
      # recursive = true;
    };
    ".config/opencode/AGENTS.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/AGENTS.md";
      force = true;
    };
    ".config/opencode/CLAUDE.md" = {
      source = config.lib.file.mkOutOfStoreSymlink "/home/asergi/dotfiles/my-opencode/CLAUDE.md";
      force = true;
    };
  };
}
