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

    uselex.rb [file1.o ... ]

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

 == REPORTING BUGS ==

     Maintainter: Sergei Trofimovich <slyfox@gentoo.org>
     Public domain.
 == The End ==
"
    exit 1
end

usage if ARGV.size == 0

require 'set'
require 'shellwords' # Shellwords::escape

# symbol => Set (files)
$defined_sym_to_files = {}
$used_sym_to_files = {}

def add_sym_def(f, sym)
    $defined_sym_to_files[sym] ||= Set.new

    $defined_sym_to_files[sym].add f
end

def add_sym_use(f, sym)
    $used_sym_to_files[sym] ||= Set.new

    $used_sym_to_files[sym].add f
end

# C++ stdlib
add_sym_use('<default>', 'operator new(unsigned int, void*)')
add_sym_use('<default>', 'main')

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

ARGV.each{|f|
    parse_file f
}

$defined_sym_to_files.each{|s,d_files|
    if $used_sym_to_files[s].nil?
        #printf("%s: redundantly exported. no external users? (exported from: %s)\n", s, d_files.to_a.join(' '))
        printf("%s: [R]: exported from: %s\n", s, d_files.to_a.join(' '))
    end
}
