# frozen_string_literal: true

require_relative "helper"
require "rubygems/indexer"

class TestGemIndexer < Gem::TestCase
  def setup
    super

    util_make_gems

    @d2_0 = util_spec "d", "2.0" do |s|
      s.date = Gem::Specification::TODAY - 86_400 * 3
    end
    util_build_gem @d2_0

    @d2_0_a = util_spec "d", "2.0.a"
    util_build_gem @d2_0_a

    @d2_0_b = util_spec "d", "2.0.b"
    util_build_gem @d2_0_b

    @default = new_default_spec "default", 2
    install_default_gems @default

    @indexerdir = File.join(@tempdir, "indexer")

    gems = File.join(@indexerdir, "gems")
    FileUtils.mkdir_p gems
    FileUtils.mv Dir[File.join(@gemhome, "cache", "*.gem")], gems

    @indexer = Gem::Indexer.new(@indexerdir)
  end

  def teardown
    FileUtils.rm_rf(@indexer.directory)
  ensure
    super
  end

  def with_indexer(dir, **opts)
    indexer = Gem::Indexer.new(dir, **opts)
    build_directory = indexer.directory
    yield indexer
  ensure
    FileUtils.rm_rf(build_directory) if build_directory
  end

  def test_initialize
    assert_equal @indexerdir, @indexer.dest_directory
    Dir.mktmpdir("gem_generate_index") do |tmpdir|
      assert_match %r{#{tmpdir.match(/.*-/)}}, @indexer.directory
    end

    with_indexer(@indexerdir) do |indexer|
      assert_predicate indexer, :build_modern
    end

    with_indexer(@indexerdir, :build_modern => true) do |indexer|
      assert_predicate indexer, :build_modern
    end
  end

  def test_build_indices
    @indexer.make_temp_directories

    use_ui @ui do
      @indexer.build_indices
    end

    specs_path = File.join @indexer.directory, "specs.#{@marshal_version}"
    specs_dump = Gem.read_binary specs_path
    specs = Marshal.load specs_dump

    expected = [["a",      Gem::Version.new("1"),   "ruby"],
                ["a",      Gem::Version.new("2"),   "ruby"],
                ["a_evil", Gem::Version.new("9"),   "ruby"],
                ["b",      Gem::Version.new("2"),   "ruby"],
                ["c",      Gem::Version.new("1.2"), "ruby"],
                ["d",      Gem::Version.new("2.0"), "ruby"],
                ["dep_x",  Gem::Version.new("1"),   "ruby"],
                ["pl",     Gem::Version.new("1"),   "i386-linux"],
                ["x",      Gem::Version.new("1"),   "ruby"]]

    assert_equal expected, specs

    latest_specs_path = File.join(@indexer.directory,
                                  "latest_specs.#{@marshal_version}")
    latest_specs_dump = Gem.read_binary latest_specs_path
    latest_specs = Marshal.load latest_specs_dump

    expected = [["a",      Gem::Version.new("2"),   "ruby"],
                ["a_evil", Gem::Version.new("9"),   "ruby"],
                ["b",      Gem::Version.new("2"),   "ruby"],
                ["c",      Gem::Version.new("1.2"), "ruby"],
                ["d",      Gem::Version.new("2.0"), "ruby"],
                ["dep_x",  Gem::Version.new("1"),   "ruby"],
                ["pl",     Gem::Version.new("1"),   "i386-linux"],
                ["x",      Gem::Version.new("1"),   "ruby"]]

    assert_equal expected, latest_specs, "latest_specs"
  end

  def test_generate_index
    use_ui @ui do
      @indexer.generate_index
    end

    quickdir = File.join @indexerdir, "quick"
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert_directory_exists quickdir
    assert_directory_exists marshal_quickdir

    assert_indexed marshal_quickdir, "#{File.basename(@a1.spec_file)}.rz"
    assert_indexed marshal_quickdir, "#{File.basename(@a2.spec_file)}.rz"

    refute_indexed marshal_quickdir, File.basename(@c1_2.spec_file)

    assert_indexed @indexerdir, "specs.#{@marshal_version}"
    assert_indexed @indexerdir, "specs.#{@marshal_version}.gz"

    assert_indexed @indexerdir, "latest_specs.#{@marshal_version}"
    assert_indexed @indexerdir, "latest_specs.#{@marshal_version}.gz"

    refute_directory_exists @indexer.directory
  end

  def test_generate_index_modern
    @indexer.build_modern = true

    use_ui @ui do
      @indexer.generate_index
    end

    refute_indexed @indexerdir, "yaml"
    refute_indexed @indexerdir, "yaml.Z"
    refute_indexed @indexerdir, "Marshal.#{@marshal_version}"
    refute_indexed @indexerdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @indexerdir, "quick"
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert_directory_exists quickdir, "quickdir should be directory"
    assert_directory_exists marshal_quickdir

    refute_indexed quickdir, "index"
    refute_indexed quickdir, "index.rz"

    refute_indexed quickdir, "latest_index"
    refute_indexed quickdir, "latest_index.rz"

    refute_indexed quickdir, "#{File.basename(@a1.spec_file)}.rz"
    refute_indexed quickdir, "#{File.basename(@a2.spec_file)}.rz"
    refute_indexed quickdir, "#{File.basename(@b2.spec_file)}.rz"
    refute_indexed quickdir, "#{File.basename(@c1_2.spec_file)}.rz"

    refute_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"
    refute_indexed quickdir, "#{File.basename(@pl1.spec_file)}.rz"

    assert_indexed marshal_quickdir, "#{File.basename(@a1.spec_file)}.rz"
    assert_indexed marshal_quickdir, "#{File.basename(@a2.spec_file)}.rz"

    refute_indexed quickdir, File.basename(@c1_2.spec_file).to_s
    refute_indexed marshal_quickdir, File.basename(@c1_2.spec_file).to_s

    assert_indexed @indexerdir, "specs.#{@marshal_version}"
    assert_indexed @indexerdir, "specs.#{@marshal_version}.gz"

    assert_indexed @indexerdir, "latest_specs.#{@marshal_version}"
    assert_indexed @indexerdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_modern_back_to_back
    @indexer.build_modern = true

    use_ui @ui do
      @indexer.generate_index
    end

    with_indexer @indexerdir do |indexer|
      indexer.build_modern = true

      use_ui @ui do
        indexer.generate_index
      end
      quickdir = File.join @indexerdir, "quick"
      marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

      assert_directory_exists quickdir
      assert_directory_exists marshal_quickdir

      assert_indexed marshal_quickdir, "#{File.basename(@a1.spec_file)}.rz"
      assert_indexed marshal_quickdir, "#{File.basename(@a2.spec_file)}.rz"

      assert_indexed @indexerdir, "specs.#{@marshal_version}"
      assert_indexed @indexerdir, "specs.#{@marshal_version}.gz"

      assert_indexed @indexerdir, "latest_specs.#{@marshal_version}"
      assert_indexed @indexerdir, "latest_specs.#{@marshal_version}.gz"
    end
  end

  def test_generate_index_ui
    use_ui @ui do
      @indexer.generate_index
    end

    assert_match %r{^\.\.\.\.\.\.\.\.\.\.\.\.$}, @ui.output
    assert_match %r{^Generating Marshal quick index gemspecs for 12 gems$},
                 @ui.output
    assert_match %r{^Complete$}, @ui.output
    assert_match %r{^Generating specs index$}, @ui.output
    assert_match %r{^Generating latest specs index$}, @ui.output
    assert_match %r{^Generating prerelease specs index$}, @ui.output
    assert_match %r{^Complete$}, @ui.output
    assert_match %r{^Compressing indices$}, @ui.output

    assert_equal "", @ui.error
  end

  def test_generate_index_specs
    use_ui @ui do
      @indexer.generate_index
    end

    specs_path = File.join @indexerdir, "specs.#{@marshal_version}"

    specs_dump = Gem.read_binary specs_path
    specs = Marshal.load specs_dump

    expected = [
      ["a",      Gem::Version.new(1),     "ruby"],
      ["a",      Gem::Version.new(2),     "ruby"],
      ["a_evil", Gem::Version.new(9),     "ruby"],
      ["b",      Gem::Version.new(2),     "ruby"],
      ["c",      Gem::Version.new("1.2"), "ruby"],
      ["d",      Gem::Version.new("2.0"), "ruby"],
      ["dep_x",  Gem::Version.new(1),     "ruby"],
      ["pl",     Gem::Version.new(1),     "i386-linux"],
      ["x",      Gem::Version.new(1),     "ruby"],
    ]

    assert_equal expected, specs

    assert_same specs[0].first, specs[1].first,
                "identical names not identical"

    assert_same specs[0][1],    specs[-1][1],
                "identical versions not identical"

    assert_same specs[0].last, specs[1].last,
                "identical platforms not identical"

    refute_same specs[1][1], specs[5][1],
                "different versions not different"
  end

  def test_generate_index_latest_specs
    use_ui @ui do
      @indexer.generate_index
    end

    latest_specs_path = File.join @indexerdir, "latest_specs.#{@marshal_version}"

    latest_specs_dump = Gem.read_binary latest_specs_path
    latest_specs = Marshal.load latest_specs_dump

    expected = [
      ["a",      Gem::Version.new(2),     "ruby"],
      ["a_evil", Gem::Version.new(9),     "ruby"],
      ["b",      Gem::Version.new(2),     "ruby"],
      ["c",      Gem::Version.new("1.2"), "ruby"],
      ["d",      Gem::Version.new("2.0"), "ruby"],
      ["dep_x",  Gem::Version.new(1),     "ruby"],
      ["pl",     Gem::Version.new(1),     "i386-linux"],
      ["x",      Gem::Version.new(1),     "ruby"],
    ]

    assert_equal expected, latest_specs

    assert_same latest_specs[0][1],   latest_specs[2][1],
                "identical versions not identical"

    assert_same latest_specs[0].last, latest_specs[1].last,
                "identical platforms not identical"
  end

  def test_generate_index_prerelease_specs
    use_ui @ui do
      @indexer.generate_index
    end

    prerelease_specs_path = File.join @indexerdir, "prerelease_specs.#{@marshal_version}"

    prerelease_specs_dump = Gem.read_binary prerelease_specs_path
    prerelease_specs = Marshal.load prerelease_specs_dump

    assert_equal [["a", Gem::Version.new("3.a"),   "ruby"],
                  ["d", Gem::Version.new("2.0.a"), "ruby"],
                  ["d", Gem::Version.new("2.0.b"), "ruby"]],
                 prerelease_specs
  end

  ##
  # Emulate the starting state of Gem::Specification in a live environment,
  # where it will carry the list of system gems
  def with_system_gems
    Gem::Specification.reset

    sys_gem = util_spec "systemgem", "1.0"
    util_build_gem sys_gem
    install_default_gems sys_gem
    yield
    util_remove_gem sys_gem
  end

  def test_update_index
    use_ui @ui do
      @indexer.generate_index
    end

    quickdir = File.join @indexerdir, "quick"
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert_directory_exists quickdir
    assert_directory_exists marshal_quickdir

    @d2_1 = util_spec "d", "2.1"
    util_build_gem @d2_1
    @d2_1_tuple = [@d2_1.name, @d2_1.version, @d2_1.original_platform]

    @d2_1_a = util_spec "d", "2.2.a"
    util_build_gem @d2_1_a
    @d2_1_a_tuple = [@d2_1_a.name, @d2_1_a.version, @d2_1_a.original_platform]

    gems = File.join @indexerdir, "gems"

    FileUtils.mv @d2_1.cache_file, gems
    FileUtils.mv @d2_1_a.cache_file, gems

    with_system_gems do
      use_ui @ui do
        @indexer.update_index
      end

      assert_indexed marshal_quickdir, "#{File.basename(@d2_1.spec_file)}.rz"

      specs_index = Marshal.load Gem.read_binary(@indexer.dest_specs_index)

      assert_includes specs_index, @d2_1_tuple
      refute_includes specs_index, @d2_1_a_tuple

      latest_specs_index = Marshal.load \
        Gem.read_binary(@indexer.dest_latest_specs_index)

      assert_includes latest_specs_index, @d2_1_tuple
      assert_includes latest_specs_index,
                      [@d2_0.name, @d2_0.version, @d2_0.original_platform]
      refute_includes latest_specs_index, @d2_1_a_tuple

      pre_specs_index = Marshal.load \
        Gem.read_binary(@indexer.dest_prerelease_specs_index)

      assert_includes pre_specs_index, @d2_1_a_tuple
      refute_includes pre_specs_index, @d2_1_tuple

      refute_directory_exists @indexer.directory
    end
  end

  def assert_indexed(dir, name)
    file = File.join dir, name
    assert File.exist?(file), "#{file} does not exist"
  end

  def refute_indexed(dir, name)
    file = File.join dir, name
    refute File.exist?(file), "#{file} exists"
  end
end
