use strict;

use Test;

use Test::Verbose;

chdir "t/pretend/lib";

my @tests = (
sub {
    ok join( ",", Test::Verbose->new->test_scripts_for( "Foo.pm" ) ),
        "t/bar.t,t/bat.t,t/baz.t,t/foo.t";
},

sub {
    ok join( ",", Test::Verbose->new->test_scripts_for( "Foo" ) ),
        "t/bar.t,t/baz.t,t/foo.t";
},

);

plan tests => 0+@tests;

$_->() for @tests;

