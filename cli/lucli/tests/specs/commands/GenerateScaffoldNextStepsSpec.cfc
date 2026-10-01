/**
 * Regression test for #3883: after `wheels generate scaffold` / `wheels
 * generate api-resource`, the printed "Next steps" told the user to
 * "Start server: wheels start" even when this project's own dev server
 * was already running. Following that advice left the newly generated
 * routes and migration un-picked-up: GET /<resource> 404'd and GET
 * /<resource>/new 500'd with Wheels.IncorrectArguments until a manual
 * `wheels reload`.
 *
 * $scaffoldNextStepsServerLine() (Module.cfc) is the single source of
 * that "Next steps" line for both commands (`generateScaffold` and
 * `generateApiResource` each call it in place of the old hardcoded
 * "Start server: wheels start" string); this spec drives it directly
 * through the two $verifyOwnServer() outcomes it switches on, via the
 * ModuleOutputCapture mocking pattern established in
 * ServerDetectionSpec.cfc (prepareMock + capture.$("$verifyOwnServer", …)).
 */
component extends="wheels.wheelstest.system.BaseSpec" {

	function beforeAll() {
		variables.testHelper = new cli.lucli.tests.TestHelper();
		variables.tempRoot = testHelper.scaffoldTempProject(expandPath("/"));
		directoryCreate(tempRoot & "/vendor/wheels", true, true);
	}

	function afterAll() {
		testHelper.cleanupTempProject(variables.tempRoot);
	}

	/**
	 * Fresh ModuleOutputCapture with $verifyOwnServer mocked to the given
	 * {port} outcome and the private $scaffoldNextStepsServerLine exposed
	 * for a direct call (it stays private in Module.cfc so it never leaks
	 * onto the MCP tools/list or the CLI subcommand surface).
	 */
	private any function captureWithOwnServerPort(required numeric port) {
		// MockBox writes its generated method stubs to /testbox/system/stubs
		// (webroot-relative) and removes them after mixing in — make sure
		// the directory exists first (same workaround ServerDetectionSpec
		// and vendor/wheels/tests/specs/controller/channelSpec.cfc use).
		createObject("java", "java.io.File").init(expandPath("/testbox/system/stubs")).mkdirs();

		var capture = new cli.lucli.tests._fixtures.commands.ModuleOutputCapture(cwd = variables.tempRoot);
		prepareMock(capture);
		capture.$(
			"$verifyOwnServer",
			{
				port: arguments.port,
				reason: arguments.port > 0 ? "" : "not-registered",
				pid: arguments.port > 0 ? "1" : "",
				hosts: arguments.port > 0 ? ["127.0.0.1"] : []
			}
		);
		makePublic(capture, "$scaffoldNextStepsServerLine");
		return capture;
	}

	function run() {

		describe("$scaffoldNextStepsServerLine — shared by generate scaffold + generate api-resource (##3883)", () => {

			it("names `wheels reload`, not `wheels start`, when this project's own server is already running", () => {
				var capture = captureWithOwnServerPort(53190);
				var line = capture.$scaffoldNextStepsServerLine();
				expect(line).toInclude("wheels reload");
				expect(line).notToInclude("wheels start");
			});

			it("names `wheels start` when no server is running for this project", () => {
				var capture = captureWithOwnServerPort(0);
				var line = capture.$scaffoldNextStepsServerLine();
				expect(line).toInclude("wheels start");
				expect(line).notToInclude("wheels reload");
			});

			it("still names `wheels start` when a server is verified NOT to be this project's own (port 0, listener-mismatch)", () => {
				// $verifyOwnServer() returns port=0 for any outcome short of a
				// proven-own server (see its own docblock) — e.g. a sibling
				// app squatting the configured port. Next steps must not
				// tell the user to reload a server that isn't theirs.
				createObject("java", "java.io.File").init(expandPath("/testbox/system/stubs")).mkdirs();
				var capture = new cli.lucli.tests._fixtures.commands.ModuleOutputCapture(cwd = variables.tempRoot);
				prepareMock(capture);
				capture.$("$verifyOwnServer", {port: 0, reason: "listener-mismatch", pid: "", hosts: []});
				makePublic(capture, "$scaffoldNextStepsServerLine");
				var line = capture.$scaffoldNextStepsServerLine();
				expect(line).toInclude("wheels start");
				expect(line).notToInclude("wheels reload");
			});

		});

	}

}
