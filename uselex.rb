#!/usr/bin/env ruby

MY_NAME    = "uselex"
MY_VERSION = "0.0.1"
NM = 'nm'
NM_OPTS = [ '-C', # demangle C++
            '-g', # only extern symbols
          ]

def usage
    print "
 == SYNOPSIS (#{MY_NAME}-#{MY_VERSION})

      uselex.rb - look for USEless EXports in object files

 == USAGE ==

    uselex.rb [ -w whitelist_file ] [ -x exported symbol ] [file1.o ... ]

 == USAGE EXAMPLE

    $ uselex.rb `find /tmp/z/bzip2-1.0.6/ -name '*.o'`
    BZ2_bzwrite: [R]: exported from: /tmp/z/bzip2-1.0.6/bzlib.o
    BZ2_bzWriteClose: [R]: exported from: /tmp/z/bzip2-1.0.6/bzlib.o
    blockSize100k: [R]: exported from: /tmp/z/bzip2-1.0.6/bzip2.o
    deleteOutputOnInterrupt: [R]: exported from: /tmp/z/bzip2-1.0.6/bzip2.o
    exitValue: [R]: exported from: /tmp/z/bzip2-1.0.6/bzip2.o

    Here we see:
    - BZ2_* false posities, as they are exported as a library interface
    - real redundant exports: blockSize100k, deleteOutputOnInterrupt, exitValue

    Thus for bzip2 the follwoing will be quite accurate:
    $ uselex.rb `find /tmp/z/bzip2-1.0.6/ -name '*.o'` | egrep -v ^BZ2_

 == THEORY OF OPERATION

    The program extracts all external symbols (with help
    of bintuils' 'nm' program) from supplied '*.o' files
    and outputs all exported, but not used internally symbols.

    For a library it's usually OK to have exported, but not used symbols,
    but for a binary it usually means lack of 'module-local' specifier
    ('static' keyword in C).

 == TODO ==

    Implement --debug / --verbose to get insight on what is going on.

 == REPORTING BUGS ==

     Maintainter: Sergei Trofimovich <slyfox@gentoo.org>
     Public domain.
 == The End ==
"
    return 1
end

require 'getoptlong'
require 'set'
require 'shellwords' # Shellwords::escape

class SymbolTracker
    def initialize
        # { symbol => Set (files_defining_symbol) }
        @defined_sym_to_files = {}
        # { symbol => Set (files_using_symbol) }
        @used_sym_to_files = {}
    end

    def add_sym_def(f, sym)
        @defined_sym_to_files[sym] ||= Set.new

        @defined_sym_to_files[sym].add f
    end

    def add_sym_use(f, sym)
        @used_sym_to_files[sym] ||= Set.new

        @used_sym_to_files[sym].add f
    end

    def parse_file(f)
        nm_cmd = sprintf("%s %s %s", NM, NM_OPTS.join(' '), Shellwords::escape(f))
        `#{nm_cmd}`.lines.each{|l|
            case l.chomp
                #0000000000b67000 A z_extract_offset
                when /^[0-9a-fA-F]+\s+A\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00000000 T _Z21GetNumberOfProcessorsv
                when /^[0-9a-fA-F]+\s+T\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00000000 W void __gnu_debug
                when /^[0-9a-fA-F]+\s+W\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00000000 V void __gnu_debug
                when /^[0-9a-fA-F]+\s+V\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #         U __stack_chk_fail
                when /^\s+U\s+(.*)$/
                    s = $1
                    add_sym_use(f, s)

                #00000001 D scanner_config::is_corrupted
                when /^[0-9a-fA-F]+\s+D\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00000000 u std::string
                when /^[0-9a-fA-F]+\s+u\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00000000 B g_lObjCount
                when /^[0-9a-fA-F]+\s+B\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00000000 R CLSID_CoVba32Ldr
                when /^[0-9a-fA-F]+\s+R\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #00002000 C g_CrcTable
                when /^[0-9a-fA-F]+\s+C\s+(.*)$/
                    s = $1
                    add_sym_def(f, s)

                #         w __pthread_key_create
                when /^\s+w\s+(.*)$/
                    s = $1
                    add_sym_use(f, s)
                else
                    raise "#{f}: unknown sym type: '#{l.chomp}'"
            end
        }
    end

    def get_result
        return @defined_sym_to_files, @used_sym_to_files
    end

    def parse_files(files)
        files.each{|f|
            parse_file f
        }
        return get_result
    end
end

def add_default_symbols(symbol_tracker)
    # C++ stdlib
    symbol_tracker.add_sym_use('<default>', 'operator new(unsigned int, void*)')
    # C executable
    symbol_tracker.add_sym_use('<default>', 'main')
end

def add_whitelist(symbol_tracker, whitelist_file)
    File.open(whitelist_file, "r"){|f|
        f.each_line{|_l|
            l = _l.chomp.strip
            next if l match(/^#/) # skip starting from '#'
            next if l == ""

            symbol = l
            symbol_tracker.add_sym_use("<whitelist:#{whitelist_file}>", symbol)
        }
    }
end

def main(config, argv)
    return usage if argv.size == 0 or config[:print_usage]

    symbol_tracker = SymbolTracker.new
    add_default_symbols symbol_tracker

    config[:whitelist_files].each{|wlf|
        add_whitelist symbol_tracker, wlf
    }
    config[:exported_symbols].each{|x_sym|
        symbol_tracker.add_sym_use("<exported:#{x_sym}>", x_sym)
    }

    defined_sym_to_files, used_sym_to_files = symbol_tracker.parse_files argv

    defined_sym_to_files.sort_by{|v| [v[1].to_a, v[0]] # module, symbol
                                 }.each{|s,d_files|
        if used_sym_to_files[s].nil?
            #printf("%s: redundantly exported. no external users? (exported from: %s)\n", s, d_files.to_a.join(' '))
            printf("%s: [R]: exported from: %s\n", s, d_files.to_a.join(' '))
        end
    }
    return 0
end

config = { :whitelist_files  => [],
           :exported_symbols => [],
           :verbose          => 0,
           :debug            => nil,
           :print_usage      => nil,
         }

opts = GetoptLong.new(
      [ '--help',          '-h', GetoptLong::NO_ARGUMENT ],
      [ '--verbose',       '-v', GetoptLong::NO_ARGUMENT ],
      [ '--version',       '-V', GetoptLong::NO_ARGUMENT ],
      [ '--debug',         '-d', GetoptLong::NO_ARGUMENT ],
      [ '--whitelist',     '-w', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--exported',      '-x', GetoptLong::REQUIRED_ARGUMENT ]
      )

opts.each{|opt, arg|
    case opt
        when '--help'
            config[:print_usage] = true
        when '--verbose'
            config[:verbose] += 1
        when '--debug'
            config[:debug] = true
        when '--version'
            config[:show_version] = true
        when '--whitelist'
            config[:whitelist_files].push arg
        when '--exported'
            config[:exported_symbols].push arg
    end
}

exit main(config, ARGV) if __FILE__ == $0
