module RSpec
  module Core
    class ExampleStatusPersister
    end

    # Merges together a list of example statuses from this run
    # and a list from previous runs (presumably loaded from disk).
    # Each example status object is expected to be a hash with
    # at least an `:example_id` and a `:status` key. Examples that
    # were loaded but not executed (due to filtering, `--fail-fast`
    # or whatever) should have a `:status` of `UNKNOWN_STATUS`.
    #
    # This willl produce a new list that:
    #   - Will be missing examples from previous runs that we know for sure
    #     no longer exist.
    #   - Will have the latest known status for any examples that either
    #     definitively do exist or may still exist.
    class ExampleStatusMerger
      def self.merge(this_run, from_previous_runs)
        new(this_run, from_previous_runs).merge
      end

      def initialize(this_run, from_previous_runs)
        @this_run           = hash_from(this_run)
        @from_previous_runs = hash_from(from_previous_runs)
        @file_exists_cache  = Hash.new { |hash, file| hash[file] = File.exist?(file) }
      end

      def merge
        delete_previous_examples_that_no_longer_exist

        @this_run.merge(@from_previous_runs) do |_ex_id, new, old|
          new.fetch(:status) == UNKNOWN_STATUS ? old : new
        end.values.sort_by(&method(:sort_value_from))
      end

      UNKNOWN_STATUS = "unknown".freeze

    private

      def hash_from(example_list)
        example_list.inject({}) do |hash, example|
          hash[example.fetch(:example_id)] = example
          hash
        end
      end

      def delete_previous_examples_that_no_longer_exist
        @from_previous_runs.delete_if do |ex_id, _|
          example_must_no_longer_exist?(ex_id)
        end
      end

      def example_must_no_longer_exist?(ex_id)
        # Obviously, it exists if it was loaded for this spec run...
        return false if @this_run.key?(ex_id)

        spec_file = spec_file_from(ex_id)

        # `this_run` includes examples that were loaded but not executed.
        # Given that, if the spec file for this example was loaded,
        # but the id does not still exist, it's safe to assume that
        # the example must no longer exist.
        return true if loaded_spec_files.include?(spec_file)

        # The example may still exist as long as the file exists...
        !@file_exists_cache[spec_file]
      end

      def loaded_spec_files
        @loaded_spec_files ||= Set.new(@this_run.keys.map(&method(:spec_file_from)))
      end

      def spec_file_from(ex_id)
        ex_id.split("[").first
      end

      def sort_value_from(example)
        file, scoped_id = example.fetch(:example_id).split(Configuration::ON_SQUARE_BRACKETS)
        [file, *scoped_id.split(":").map(&method(:Integer))]
      end
    end

    # Dumps a list of hashes in a pretty, human readable format
    # for later parsing. The hashes are expected to have symbol
    # keys and string values, and each hash should have the same
    # set of keys.
    class ExampleStatusDumper
      def self.dump(examples)
        new(examples).dump
      end

      def initialize(examples)
        @examples = examples
      end

      def dump
        return nil if @examples.empty?
        (formatted_header_rows + formatted_value_rows).join("\n") << "\n"
      end

    private

      def formatted_header_rows
        @formatted_header_rows ||= begin
          dividers = column_widths.map { |w| "-" * w }
          [ formatted_row_from(headers.map(&:to_s)), formatted_row_from(dividers) ]
        end
      end

      def formatted_value_rows
        @foramtted_value_rows ||= rows.map do |row|
          formatted_row_from(row)
        end
      end

      def rows
        @rows ||= @examples.map { |ex| ex.values_at(*headers) }
      end

      def formatted_row_from(row_values)
        padded_values = row_values.each_with_index.map do |value, index|
          value.ljust(column_widths[index])
        end

        padded_values.join(" | ") << " |"
      end

      def headers
        @headers ||= @examples.first.keys
      end

      def column_widths
        @column_widths ||= begin
          value_sets = rows.transpose

          headers.each_with_index.map do |header, index|
            values = value_sets[index] << header.to_s
            values.map(&:length).max
          end
        end
      end
    end

    class ExampleStatusParser
      def self.parse(string)
        new(string).parse
      end

      def initialize(string)
        @header_line, _divider, *@row_lines = string.lines
      end

      def parse
        @row_lines.map { |line| parse_row(line) }
      end

    private

      def parse_row(line)
        Hash[ headers.zip(split_line(line)) ]
      end

      def headers
        @headers ||= split_line(@header_line).map(&:to_sym)
      end

      def split_line(line)
        line.split(/\s+\|\s+/)
      end
    end
  end
end
