const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build shared library") orelse true;
    const reuse_allocator = b.option(bool, "reuse-allocator", "Reuse tree-sitter allocator") orelse false;

    const lib_name = "tree-sitter-python";

    const lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = if (shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = if (shared) true else null,
        }),
    });

    lib.root_module.addIncludePath(b.path("src"));

    // Core sources
    const base_sources = [_][]const u8{"src/parser.c"};

    const c_sources: []const []const u8 = if (fileExists(b, "src/scanner.c"))
        &(base_sources ++ [_][]const u8{"src/scanner.c"})
    else
        &base_sources;

    lib.root_module.addCSourceFiles(.{
        .files = c_sources,
        .flags = &[_][]const u8{
            "-std=c11",
            "-fno-sanitize=undefined",
            "-O2",
        },
    });

    if (reuse_allocator) {
        lib.root_module.addCMacro("TREE_SITTER_REUSE_ALLOCATOR", "");
    }
    if (optimize == .Debug) {
        lib.root_module.addCMacro("TREE_SITTER_DEBUG", "");
    }

    b.installArtifact(lib);
    b.installFile("src/node-types.json", "node-types.json");

    if (fileExists(b, "queries")) {
        b.installDirectory(.{
            .source_dir = b.path("queries"),
            .install_dir = .prefix,
            .install_subdir = "queries",
            .include_extensions = &.{"scm"},
        });
    }

    // Zig bindings module
    const module = b.addModule(lib_name, .{
        .root_source_file = b.path("bindings/zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bindings/zig/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport(lib_name, module);

    // tree-sitter dep only needed for tests → lazy fetch happens automatically when test runs
    if (b.lazyDependency("tree_sitter", .{})) |ts_dep| {
        tests.root_module.addImport("tree-sitter", ts_dep.module("tree_sitter"));
    }

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

fn fileExists(b: *std.Build, filename: []const u8) bool {
    b.build_root.handle.access(b.graph.io, filename, .{}) catch return false;
    return true;
}
