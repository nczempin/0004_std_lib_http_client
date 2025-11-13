const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the library
    const httpzig_module = b.addModule("httpzig", .{
        .root_source_file = b.path("lib.zig"),
    });

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Benchmark executable (for later phases)
    const benchmark_exe = b.addExecutable(.{
        .name = "httpzig_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    benchmark_exe.root_module.addImport("httpzig", httpzig_module);

    const install_benchmark = b.addInstallArtifact(benchmark_exe, .{});
    const benchmark_step = b.step("benchmark", "Build benchmark executable");
    benchmark_step.dependOn(&install_benchmark.step);

    // Integration test executable
    const integration_test_exe = b.addExecutable(.{
        .name = "httpzig_integration_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    integration_test_exe.root_module.addImport("httpzig", httpzig_module);

    const install_integration_test = b.addInstallArtifact(integration_test_exe, .{});
    const integration_test_step = b.step("integration-test", "Build integration test executable");
    integration_test_step.dependOn(&install_integration_test.step);

    const run_integration_test = b.addRunArtifact(integration_test_exe);
    const run_integration_step = b.step("run-integration", "Run integration test");
    run_integration_step.dependOn(&run_integration_test.step);
}
