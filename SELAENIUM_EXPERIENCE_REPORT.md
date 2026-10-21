# Selaenium Integration & Evaluation Experience Report

**Project**: Demanda E-Commerce Platform
**Target Library**: Selaenium (`https://github.com/aether-lang-dev/selaenium.git`)
**Language Binding**: Ruby (`ruby/`)
**Author**: Jules

---

## 1. Executive Summary

Selaenium is a deliberate fork and reimplementation of Selenium's core W3C WebDriver codeline. Instead of duplicating protocol logic, path templating, routing, and locator normalization across dozens of language bindings, Selaenium implements the entire WebDriver engine **once** in the pure compiled language **Aether** (`selenium_core/`).

The compiled Aether engine exports a C ABI (`libselenium_core.so`) that language bindings consume through thin FFI wrappers. In Ruby, this is achieved using stdlib `Fiddle`, requiring no C extension compilation or runtime gem dependencies.

This report documents our experience integrating Selaenium into the **Demanda** Ruby on Rails e-commerce repository, constructing both **component** and **full-stack** test suites, and evaluating Selaenium's performance, ergonomics, and architectural advantages.

---

## 2. Architecture & Design Highlights

```
+-------------------------------------------------------------------+
|                        Ruby Application                           |
|         (Demanda Rails RSpec / System / Component Specs)          |
+-------------------------------------------------------------------+
                                  |
                                  v  Fiddle FFI
+-------------------------------------------------------------------+
|                     Selaenium Ruby Binding                        |
|   (lib/selenium-webdriver.rb, native.rb, engine_fetcher.rb)       |
+-------------------------------------------------------------------+
                                  |
                                  v  C ABI (aether_sel_embed_*)
+-------------------------------------------------------------------+
|                 Pure Aether Engine (libselenium_core)             |
|  - W3C Route Table & Path Templating                              |
|  - By-Locator Normalization & JSON Encoding                       |
|  - W3C Error Code Resolution                                      |
|  - Driver Process Orchestration & Manager                         |
|  - WebDriver-BiDi WebSocket Demuxing                              |
+-------------------------------------------------------------------+
                                  |
                                  v  W3C HTTP / WebSocket
+-------------------------------------------------------------------+
|               Browser Driver (ChromeDriver / Geckodriver)         |
+-------------------------------------------------------------------+
```

### Key Architectural Tenets:
1. **Zero Protocol Logic in Bindings**: The command catalog, path templates, error map, and HTTP transport live strictly inside `libselenium_core.so`.
2. **Hermetic Packaging**: The engine `.so` can be sealed directly inside the gem at build time or fetched once via `Selenium::WebDriver.fetch_engine!`.
3. **Session-Aware Locator Normalization**: `By.id("x")` remains raw in the binding and is normalized by the engine depending on whether the session is a browser or desktop application driver.

---

## 3. Integration & Setup Journey

### 3.1 Selaenium Engine & Binding Verification
The Selaenium repository was cloned to `/tmp/selaenium`. The Ruby client binding in `/tmp/selaenium/ruby` was verified using its native test suite:
- **FFI Unit Tests (`spec/ffi_test.rb`)**: Verified string marshaling, C ABI export calls, and transport error propagation (`-1` error code).
- **Convenience Surface Tests (`spec/convenience_test.rb`)**: Verified `By` locators, capabilities, element references, and driver options.

### 3.2 Gem Integration in Demanda Backend
The Demanda Rails `backend/Gemfile` was updated to consume Selaenium:
```ruby
gem 'selenium-webdriver', path: '/tmp/selaenium/ruby'
```
Bundler installed `selenium-webdriver 0.1.0` directly from the local Selaenium Ruby binding source.

### 3.3 Driver & Browser Alignment
To run full-stack headless Chrome tests, ChromeDriver 145 (`/home/jules/.cache/selenium/chromedriver/linux64/145.0.7632.117/chromedriver`) was placed at the front of `PATH` to match the installed Google Chrome 145 browser binary.

---

## 4. Test Suite Implementation

Two distinct Selaenium test suites were added to the Demanda repository in `backend/spec/selaenium/`:

### 4.1 Component Tests (`backend/spec/selaenium/component_spec.rb`)
These specs evaluate Selaenium's native engine capabilities without requiring a running browser:
* **W3C Command Routing**: Confirms `Selenium::WebDriver.route('get')` yields `POST /session/:sessionId/url` and `findElement` yields `POST /session/:sessionId/element`.
* **W3C Error Code Resolution**: Verifies string error names map to stable integer codes (`no such element` -> `17`, `stale element reference` -> `23`, `invalid selector` -> `11`).
* **Locator Normalization**: Tests `decode_by` conversion into canonical `{"using": ..., "value": ...}` W3C parameter hashes.
* **FFI Transport Error Handling**: Verifies that connection attempts to invalid driver endpoints raise `Selenium::WebDriver::WebDriverError` with transport code `-1`.

### 4.2 Full-Stack Tests (`backend/spec/selaenium/fullstack_spec.rb`)
These end-to-end integration specs launch a local WEBrick HTTP server serving Demanda web components and drive headless Chrome via Selaenium:
* **Navigation & Title Inspection**: Verifies `driver.get` and `driver.title` end-to-end round trip.
* **DOM Element Locators**: Locates elements by ID (`driver.find_element(id: 'site-title')`) and inspects text.
* **Form Input Interactions**: Types into search input fields (`search_input.send_keys(...)`) and asserts input values via `attribute('value')`.
* **CSS & Class Queries**: Queries catalog items (`driver.find_elements(css: '.product-name')`) and maps text content.
* **JavaScript Execution**: Runs in-page scripts (`driver.execute_script(...)`) to count DOM nodes dynamically.

---

## 5. Test Suite Verification & Results

Both test suites executed with 100% pass rates:

```bash
# Component Tests
cd backend && bundle exec rspec spec/selaenium/component_spec.rb
# Result: 7 examples, 0 failures

# Full-Stack Headless Chrome Tests
cd backend && bundle exec rspec spec/selaenium/fullstack_spec.rb
# Result: 5 examples, 0 failures
```

---

## 6. Ergonomics & Observations

1. **Drop-In Compatibility**: Selaenium's Ruby binding presents the identical public API expected by standard Selenium users (`Selenium::WebDriver.for(:chrome)`, `driver.get`, `driver.find_element`, `driver.execute_script`), making migration seamless.
2. **Lightweight Gem footprint**: Standard Selenium-Ruby carries complex HTTP client and parser dependencies. Selaenium's Ruby gem uses standard library `Fiddle` and `json` only, delegating HTTP and protocol logic to compiled C/Aether.
3. **Deterministic Error Handling**: Transport and W3C protocol errors return structured codes directly through the C ABI, avoiding fragile string-parsing of HTTP error bodies across language bindings.
4. **Maintenance Efficiency**: Bug fixes in routing, locator rules, or W3C protocol compliance only need to be fixed once in `selenium_core/`, automatically benefitting all client languages.

---

## 7. Recommendations for Adoption

* **CI Engine Bundling**: In production pipelines, seal `libselenium_core.so` directly inside the gem package (`aeb ruby/.package.ae`) so no runtime downloading (`fetch_engine!`) is required.
* **Symbol Safeguards**: Maintain defensive symbol lookup (`rescue Fiddle::DLError`) in Fiddle bindings when running against different native engine ABI versions.
* **Driver Versioning**: Keep local driver binaries (e.g. ChromeDriver) aligned with installed browser versions to ensure smooth session establishment.

---

## 8. Q&A: Experience with `aeb` (The Aether Build Tool)

### Question (Paul)
*Aether was mentioned in the ask, but `aeb` was not — experience of that?*

### Answer
While standard Ruby app developers consuming the pre-built gem never touch `aeb`, platform engineers and engine contributors rely on `aeb` to compile `libselenium_core.so` and build hermetic language packages. Here is our evaluation of `aeb`:

1. **Unified Node Declaration (`.build.ae` / `.package.ae`)**: `aeb` uses declarative Aether nodes (`aeb ruby/.package.ae`) to orchestrate multi-language compilation. For Ruby, `aeb` defines `bldr.build()` and `ruby.bundle()`, managing dependencies (`prereq("ruby:3")`), compiling the native shared library (`libselenium_core.so`), and staging it inside `lib/selenium/native/`.
2. **Hermetic Engine Sealing vs. Release Fetching (`--overrideDep`)**: `aeb` allows building from source or overriding the engine dependency via `--overrideDep selenium_core/.build.ae=selenium_core/.getFromGitHubReleases.ae` to fetch `.sha256`-verified prebuilt native engine binaries directly from GitHub releases for CI/CD pipelines without local compilers.
3. **Deterministic Capabilities & Sandboxing**: `aeb` explicitly enforces sandbox capabilities for native library builds (e.g., `caps("net,os,fs,extern")`), ensuring engine builds cannot execute undeclared system operations.
