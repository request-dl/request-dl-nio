# Pull Request Contributions Guidelines

Thank you for your interest in contributing to this project! We welcome any pull requests that add value to the project and help improve its functionality.

To ensure that your pull request is reviewed and accepted in a timely manner, please follow these guidelines:

## Contributing

1. Before contributing, please check the issues page to see if the feature or bug fix you would like to contribute has already been addressed.
2. If the issue has not been addressed, please create a new issue to discuss the proposed change with the maintainers.
3. Fork the repository and create a new branch for your changes.
4. Write your code and commit your changes to your branch.
5. Test your changes thoroughly.
6. Create a pull request and describe your changes in detail.
7. Be open to feedback and be prepared to make any necessary changes based on feedback from the maintainers.

## Code Standards

1. Please ensure that your code adheres to the project's existing code standards and style guidelines.
2. Follow the naming conventions and code organization used in the project.
3. Keep your code clean, organized, and easy to read.
4. Document your code using inline comments and docstrings as appropriate.

## Testing

1. Your code should be thoroughly tested using automated tests.
2. Tests should cover as much of your code as possible to ensure that it is reliable and bug-free.
3. Ensure that all existing tests pass before submitting your pull request.
4. Include any new or updated tests that are required to validate your changes.

### Running the tests

1. The package builds in two configurations: the default one (`swift test`) and without the `NIOTransport` trait (`swift build --disable-default-traits`). Run both before submitting a change.
2. Give the second one a build directory of its own, `swift build --disable-default-traits --scratch-path .build-notnio`. Right after a default `swift test`, building it in `.build` fails with `clang dependency scanning failure` and no further detail.
3. A test run that was killed can leave a `swiftpm-testing-helper` process holding the ports of the test servers, and the next run fails with `Address already in use`. Look for the leftover process and end it.
4. To run the whole suite on Linux with the Apple `container` tool, copy the tree without `.build`, `.git` and `.claude` and run `swift test` in a `swift:6.2` container (`container run --rm -c 8 -m 12g -v <copy>:/src:ro -w /work swift:6.2 bash -c 'cp -r /src/. /work && swift test'`). Copy it while no test run is going on the host, because some tests leave large files in the tree while they run and the copy would carry them. Run it with nothing else heavy on the machine: on a loaded one, tests against a local server fail with `connectTimeout`, which says nothing about the change.
5. A test that waits for time to pass should take an injected clock instead of sleeping for a real window, and a test must not compare numbers of the whole process (threads, descriptors) while the suite runs in parallel. Prefer a probe on the object under test.
6. A test that depends on a time limit does not use the machine's clock for it. A request's read timeout is checked against a clock a test can move (`FakeIdleClock`, bound with `Internals.IdleDeadline.$clock`), because the test process stalls for seconds in a full run on a loaded runner: a test with a one second budget took fourteen, and failed for it, twice in a row on Linux and never in isolation. Moving the clock also made the suite of those tests run in a third of the time.
7. A test that waits for a request the server recorded uses `awaitRecordedRequests`, with a closure to pick the requests it means. When it gives up it says what the server did record, which tells a request that never came from one that came different, and a CI log has nothing else to go on. A test never awaits a request without a bound (`completing(within:)`, or `Running` in `ReadTimeoutTests`): a request that does not end is a failed test, and not a job cancelled at its time limit with nothing in its log.

## Review Process

1. Once you have submitted your pull request, the maintainers will review it as soon as possible.
2. Please be patient while waiting for a review, as the maintainers may be busy with other tasks.
3. The maintainers will provide feedback on your changes and suggest any necessary changes.
4. Once your changes have been reviewed and approved, they will be merged into the project's main branch.
5. The CI workflow does not run on a draft pull request (`swift-ci.yaml` skips them at the job level). Mark it ready for review to run it.

Thank you for contributing to this project!
