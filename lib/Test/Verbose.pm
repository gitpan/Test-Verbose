package Test::Verbose;

$VERSION = 0.000_2;

=head1 NAME

   Test::Verbose - Run 'make TEST_VERBOSE=1' on one or more test files

=head1 SYNOPSIS


    use Test::Verbose qw( test_verbose );
    test_verbose( @module_and_test_script_filenames );

For more control, you can use the object oriented interface.

See also the L<tv> command.

=head1 DESCRIPTION

Given a list of test scripts, source file names, directories and/or
package names, attempts to find and execute the appropriate test
scripts.

This (via the associated tv command) is useful when developing code or
test scripts: just map "tv %" to a key in your editor and press it
frequently (where "%" is your editor's macro for "the file being
edited).

Before doing anything, this module identifies the working directory for
the project by scanning the current directory and it's ancestors,
stopping at the first directory that contains a "t" directory.

If an explicitly named item cannot be tested, an exception is thrown.

Here is how each name passed in is treated:

=over

=item test script

An explicitly mentioned test script is selected, no source files need be
parsed.  Names of test scripts are recognized by ending in ".t" and, if
they exist on the filesystem, by being a file (and not a directory).

=item source file

Source files are parsed (very naively) looking for C<package> declarations
and for test scripts listed in special POD comments:

    =for test_script foo.t bar.t
        baz.t

Also, all test scripts are parsed looking for C<use> and C<require>
statements and for POD that looks like:

    =for file lib/Foo.pm

or

    =for package Foo

.  All test scripts pertaining to a given file and any packages in it
are then selected.

The paths listed in C<=for file> must be paths relative to the project
root and not contain "..".  Hmmm, they can also be absolute paths, but
why would you do that?

Names of source files are recognized by not ending in ".t" and not
looking like a package name or, if they do look like a package name, by
existing on the filesystem.

=item directory

Directories are travered looking for files with the extensions ".t",
".pm", or ".pl".  These are then treated as though they had been
explicitly named.  Note that this notion of "looks like a source file"
differs from that used when a source file is explicitly passed (where
any extension other than .t may be used).

=item package name

If a name looks like a legal package name (Contains only word characters
and "::" digraphs) and does not exist on the filesystem, then it is
assumed to be a package name.  In this case, all explicitly mentioned
source files and test script files are scanned as normal, as well as
those found by scanning the main project directory and (only) it's lib
and t subdirectories.  Files found there are not selected, but are used
to determine what tests to run for a package.

=back

=head1 FUNCTIONS

    test_verbose( @names );
    test_verbose( @names, \%options );

Shortcut for

    my $tv = Test::Verbose->new( %options )->exec_make_test( @names );

=cut

@EXPORT_OK = qw( test_verbose );
@ISA = qw( Exporter );

use strict;

use constant debugging => $ENV{TVDEBUG} ? 1 : 0;

BEGIN {
    require Exporter;
    require Carp;
    require Cwd;
    require File::Spec;
}

sub test_verbose {
    my $options = ref $_[-1] eq "HASH" ? pop : {};
    Test::Verbose->new( %$options )->exec_make_test( @_ );
}

=head1 METHODS

=over

=item new 

Takes a list of options:

=over

=item Dir

What directory to look for t/ and run make(1) in.  Undefined causes
the instance to search for a directory containing a directory named "t"
in the current directory and its parents.

=item JustPrint

Print out the command to be executed.

=back

=cut

sub new {
    my $proto = shift;
    return bless { @_ }, ref $proto ? ref $proto : $proto;
}

=item dir

    my $dir = $tv->dir;
    $tv->dir( undef );   ## clear old setting
    $tv->dir( "foo" );   ## prevent chdir( ".." ) searching

Looks for t/ in the current directory or in any parent directory.
C<chdir()>s up the directory tree until t/ is found, then back to the
directory it started in, so make sure you have permissions to C<chdir()>
up and back.

Passing a Dir => $dir option to new prevents this method for searching
for a name,

=cut

sub dir {
    my $self = shift;

    $self->{Dir} = shift if @_;
    
    if ( defined wantarray && ! defined $self->{Dir} ) {
        warn "Searching for project directory\n" if debugging;
        my $cwd = Cwd::cwd;
        ## cd up until we find a directory that has a "t" subdirectory
        ## this is for folks whose editor's working directories might be
        ## down in t/ or lib/, etc.
        chdir File::Spec->updir or die "$! while cd()ing upwards looking for t/"
            until -d "t";
        $self->{Dir} = Cwd::cwd;
        warn "...found $self->{Dir}\n" if debugging;
        chdir $cwd or die "$! chdir()ing back to '$cwd'";
    }

    return $self->{Dir};
}


=item is_test_script

    $self->is_test_script;         ## tests $_
    $self->is_test_script( $name );

Returns true if the name looks like the name of a test script (ends in .t).
File does not need to exist.

Overload this to alter Test::Verbose's perceptions.

=cut

sub is_test_script {
    my $self = shift;
    local $_ = shift if @_;
    /\.t\z/ && ( ! -e || -f _ );
}


=item is_source_file

    $self->is_source_file;         ## tests $_
    $self->is_source_file( $name );

Returns true if the name looks like the name of a test script (ends in
.pm or .pl).  File does not need to exist, but must be a file if it
does.

Overload this to alter Test::Verbose's perceptions.

=cut

sub is_source_file {
    my $self = shift;
    local $_ = shift if @_;
    /\.(pm|pl)\z/ && ( ! -e || -f _ );
}


=item is_package

    $self->is_test_script; ## tests $_
    $self->is_test_script( $name );

Returns trues if the name looks like the name of a package (contains
only /\w/ and "::") and is not a name that exists (ie C<! -e>).

Overload this to alter Test::Verbose's perceptions.

=cut


sub is_package {
    my $self = shift;
    local $_ = shift if @_;
    /\A(\w|::)+\z/ && ! -e;
}


=item unhandled

    $self->unhandled( @_ );

die()s with any unhandled names.

Overload this to alter the default.

=cut

sub die_unhandled {
    my $self = shift;

    die "No test scripts found for: ", join( ", ", @_ ), "\n",
            "Try adding '=for test_script ...' to the source",
            @_ > 1 ? "s" : "",
            " or 'use ...;' or '=for package ...' to the test scripts\n";
}

=item look_up_scripts

    my @scripts = $tv->look_up_test_scripts( @_ );

Looks up the scripts for any names that don't look like test scripts.

die()s if a non-test script cannot be found.

use =for tv dont_test to prevent this error.

All test scripts returned will have the form "t/foo.t", and the result
is sorted.  No test script name will be returned more than once.

=cut

sub test_scripts_for {
    my $self = shift;

    my @test_scripts;
    my @oops;

    local $self->{Names} = [ $self->_traverse_dirs( @_ ) ];

    for ( @{$self->{Names}} ) {
        if ( $self->is_test_script ) {
            push @test_scripts, $_;
        }
        elsif ( $self->is_package ) {
            my @t = $self->test_scripts_for_package;
            if ( @t ) {
                push @test_scripts, @t;
            }
            else {
                push @oops, $_;
            }
        }
        elsif ( -d ) {
            my @t = $self->test_scripts_for_dir;
            if ( @t ) {
                push @test_scripts, @t;
            }
            else {
                push @oops, $_;
            }
        }
        else {
            my @t = $self->test_scripts_for_file;
            if ( @t ) {
                push @test_scripts, @t;
            }
            else {
                push @oops, $_;
            }
        }
    }

    $self->die_unhandled( @oops ) if @oops;

    my %seen;
    return sort grep !$seen{$_}++, map {
        ## Make all test scripts look like "t/foo.t"
        $_ = File::Spec->canonpath( $_ );
        s{^(t[\\/])?}{t/};
        $_;
    } @test_scripts
}


sub _slurp_and_split {
    my @items = split /\s+/, $1;
    local $_;
    while (<F>) {
        last if /^$/;
        push @items, split /\s+/;
    }

    return grep length, @items;
}


sub _traverse_dirs {
    my $self = shift;
    my @names = @_;

    return map {
        my $dir = $_;
        -d $dir
            ? do {
                my @results;
                warn "traversing $_\n" if debugging;
                require File::Find;
                File::Find::find(
                    sub {
                        if (
                            -f
                                && ( $self->is_source_file ||
                                     $self->is_test_script
                                 )
                        ) {
                            push @results, $File::Find::name;
                            push @{$self->{FilesInDir}->{$dir}},
                                $File::Find::name;
                        }
                    },
                    $_
                );
                @results ? @results : $_;
            }
            : $dir;
    } @names;
}


sub _scan_source_files {
    my $self = shift;

    my @files = grep ! $self->is_package && ! $self->is_test_script,
        @{$self->{Names}};

    if ( @files < @{$self->{Names}} ) {
        ## Scan all likely source files to look for those that
        ## might contain the package.
        push @files,
            $self->_traverse_dirs( File::Spec->catdir( $self->dir, 'lib') ),
            do {
                opendir D, $self->dir;
                my @f = grep
                    -f && $self->is_source_file,
                    readdir D;
                close D;
                @f = map File::Spec->catdir( $self->dir, $_ ), @f;
            };
    }

    my $cwd = Cwd::cwd;

    for my $code_file ( @files ) {
        warn "Scanning code file $code_file\n" if debugging;
        open F, $code_file or die "$!: $code_file";
        my $abs_fn = File::Spec->canonpath(
            File::Spec->rel2abs( $code_file, $cwd )
        );

        my $package = "main";
        local $/ = "\n";
        local $_;
        while (<F>) {
            if ( /^=for\s+test_scripts?\s+(.*)/ ) {
                my @scripts = _slurp_and_split;
                warn "$abs_fn, $package =for test_scripts ", join( " ", @scripts ), "\n"
                    if debugging;
                push @{$self->{Files}->{$abs_fn}}, @scripts;
                push @{$self->{Packages}->{$package}}, @scripts;
            }
            elsif ( /^\s*package\s+(\S+);/ ) {
                $package = $1;
                warn "$abs_fn contains $package\n" if debugging;
                push @{$self->{PackagesForFile}->{$abs_fn}}, $package;
            }
        }
        close F or die "$! closing $code_file";
    }

    1;
}


sub _scan_test_scripts {
    my $self = shift;

    my $cwd = Cwd::cwd;

    chdir $self->dir or Carp::croak "$!: ", $self->dir, "\n";
    my @all_test_scripts = grep /.t\z/, $self->_traverse_dirs( "t" );
    chdir $cwd or Carp::croak "$!: $cwd\n";

    die "No test scripts (t/*.t) found\n" unless @all_test_scripts;

    for my $test_script ( @all_test_scripts ) {
        warn "Scanning test script $test_script\n" if debugging;
        open F, File::Spec->catfile( $self->dir, $test_script )
            or Carp::croak "$!: $test_script\n";

        local $/ = "\n";
        local $_;
        while (<F>) {
            if ( /^=for\s+packages?\s+(.*)/ ) {
                my @pkgs = _slurp_and_split;
                warn "$test_script =for packages ", join( " ", @pkgs ), "\n"
                    if debugging;
                map push( @{$self->{Packages}->{$_}}, $test_script ), @pkgs;
            }
            elsif ( /^=for\s+files?\s+(.*)/ ) {
                my @files = map
                    File::Spec->canonpath(
                        File::Spec->rel2abs( $_, $self->dir )
                    ), _slurp_and_split;
                warn "$test_script =for files ", join( " ", @files ), "\n"
                    if debugging;
                map
                    push( @{$self->{Files}->{$_}}, $test_script ),
                    @files;
            }
            elsif ( /\s*(use|require)\s+([\w:]+)/ ) {
                warn "$test_script $1s $2\n" if debugging;
                push @{$self->{Packages}->{$2}}, $test_script;
            }
        }
        close F or die "$! closing $test_script";
    }

    1;
}


sub test_scripts_for_package {
    my $self = shift;
    local $_ = shift if @_;

    $self->{ScannedSourceFiles} ||= $self->_scan_source_files;
    $self->{ScannedTestScripts} ||= $self->_scan_test_scripts;

    return exists $self->{Packages}->{$_}
        ? @{$self->{Packages}->{$_}}
        : ();
}


sub test_scripts_for_file {
    my $self = shift;
    local $_ = shift if @_;

    $self->{ScannedSourceFiles} ||= $self->_scan_source_files;
    $self->{ScannedTestScripts} ||= $self->_scan_test_scripts;

    local $_ = File::Spec->canonpath(
        File::Spec->rel2abs( $_, Cwd::cwd )
    );

    return (
        exists $self->{Files}->{$_}
            ? @{$self->{Files}->{$_}}
            : (),
        exists $self->{PackagesForFile}->{$_}
            ? map $self->test_scripts_for_package,
                @{$self->{PackagesForFile}->{$_}}
            : (),
    );
}


sub test_scripts_for_dir {
    my $self = shift;
    local $_ = shift if @_;

    $self->{ScannedSourceFiles} ||= $self->_scan_source_files;
    $self->{ScannedTestScripts} ||= $self->_scan_test_scripts;

    return
        exists $self->{FilesInDir}->{$_}
            ? map
                $self->is_test_script
                    ? $_
                    : $self->test_scripts_for_file,
                @{$self->{FilesInDir}->{$_}}
            : ();
}


=item exec_make_test

    $self->exec_make_test( @test_scripts );

chdir()s to C<$self->dir> and C<exec()>s make test.  Does not return.

=cut

sub exec_make_test {
    my $self = shift;

    my $test_files = "TEST_FILES=" . join " ", $self->test_scripts_for( @_ );

    my $cwd = Cwd::cwd;
    my $d = $self->dir;
    chdir $d or die "$!: $d";

    my @cmd = ( qw( make test TEST_VERBOSE=1 ), $test_files );

    if ( $self->{JustPrint} ) {
        print
            join " ", map (
            m{[^\w./\\=-]}
                ? do {
                    s/([\\'])/\\$1/g;
                    "'$_'";
                }
                : $_, @cmd
            ),
            "\n";
        exit 0;
    }

    { exec @cmd }
    chdir $cwd or warn "$! chdir( '$cwd' )\n";;
    die "$!: ", join " ", @cmd;
}

=back

=head1 ASSumptions and LIMITATIONS

=over

=item * 

Test scripts with spaces in their filenames will screw up, since these
are interpolated in to a single, space delimited make(1) variable like so:

    make test TEST_VERBOSE=1 "TEST_FILES=t/spaced out name.t"

=item *

Your make must be called "make".  I will alter this assumption as soon
as I need this on Win32 again.  Feel free to submit patches.

=item *

Speaking of which, although this module has a nod to portability, it
has not been tested on platforms other than Unix, so there be dragons
there.  They should be easy to fix, so please patch away.

=item *

The source code scanners look for /^\s*(use|require)\s+([\w:])/ (in test
scripts) and /^\s*package\s+(\S+);/, and so are easily fooled.

=back

=cut

=head1 COPYRIGHT

    Copyright 2002 R. Barrie Slaymaker, All Rights Reserver

=head1 LICENSE

You may use this module under the terms of the BSD, GNU, or Artistic
licenses.

=head1 AUTHOR

    Barrie Slaymaker <barries@slaysys.com>

=cut

1;
