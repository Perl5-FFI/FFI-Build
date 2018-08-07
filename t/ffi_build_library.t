use strict;
use warnings;
use Test::More;
use lib 't/lib';
use Test::Cleanup;
use FFI::Build::Library;
use FFI::Build::Platform;
use File::Temp qw( tempdir );
use Capture::Tiny qw( capture_merged );
use File::Spec;
use File::Path qw( rmtree );
use FFI::Platypus;

subtest 'basic' => sub {

  my $lib = FFI::Build::Library->new('foo');
  isa_ok $lib, 'FFI::Build::Library';
  like $lib->file->path, qr/foo/, 'foo is somewhere in the native name for the lib';
  note "lib.file.path = @{[ $lib->file->path ]}";

  ok(-d $lib->file->dirname, "dir is a dir" );
  isa_ok $lib->platform, 'FFI::Build::Platform';

  $lib->source('corpus/*.c');
  
  my($cfile) = $lib->source;
  isa_ok $cfile, 'FFI::Build::File::C';

};

subtest 'file classes' => sub {
  {
    package FFI::Build::File::Foo1;
    use base qw( FFI::Build::File::Base );
    $INC{'FFI/Build/File/Foo1.pm'} = __FILE__;
  }

  {
    package FFI::Build::File::Foo2;
    use base qw( FFI::Build::File::Base );
  }

  my @list = FFI::Build::Library::_file_classes();
  ok( @list > 0, "at least one" );
  note "class = $_" for @list;
};

subtest 'build' => sub {

  my $lib = FFI::Build::Library->new('foo', 
    dir       => tempdir( "tmpbuild.XXXXXX", DIR => 'corpus/ffi_build_library/project1' ),
    buildname => "tmpbuild.tmpbuild.$$.@{[ time ]}",
    verbose   => 1,
  );
  
  $lib->source('corpus/ffi_build_library/project1/*.c');
  note "$_" for $lib->source;

  my($out, $dll, $error) = capture_merged {
    my $dll = eval { $lib->build };
    ($dll, $@);
  };

  ok $error eq '', 'no error';

  if($error)
  {
    diag $out;
    return;
  }
  else
  {
    note $out;
  }
  
  my $ffi = FFI::Platypus->new;
  $ffi->lib($dll);
  
  is(
    $ffi->function(foo1 => [] => 'int')->call,
    42,
  );

  is(
    $ffi->function(foo2 => [] => 'string')->call,
    "42",
  );

  cleanup(
    $lib->file->dirname,
    File::Spec->catdir(qw( corpus ffi_build_library project1 ), $lib->buildname)
  );

};

subtest 'build c++' => sub {

  plan skip_all => 'Test requires C++ compiler'
    unless FFI::Build::Platform->which(FFI::Build::Platform->cxx);

  my $lib = FFI::Build::Library->new('foo', 
    dir       => tempdir( "tmpbuild.XXXXXX", DIR => 'corpus/ffi_build_library/project-cxx' ),
    buildname => "tmpbuild.$$.@{[ time ]}",,
    verbose   => 1,
  );
  
  $lib->source('corpus/ffi_build_library/project-cxx/*.cxx');
  $lib->source('corpus/ffi_build_library/project-cxx/*.cpp');
  note "$_" for $lib->source;

  my($out, $dll, $error) = capture_merged {
    my $dll = eval { $lib->build };
    ($dll, $@);
  };

  ok $error eq '', 'no error';

  if($error)
  {
    diag $out;
    return;
  }
  else
  {
    note $out;
  }
  
  my $ffi = FFI::Platypus->new;
  $ffi->lib($dll);
  
  is(
    $ffi->function(foo1 => [] => 'int')->call,
    42,
  );

  is(
    $ffi->function(foo2 => [] => 'string')->call,
    "42",
  );

  cleanup(
    $lib->file->dirname,
    File::Spec->catdir(qw( corpus ffi_build_library project-cxx ), $lib->buildname)
  );

};

subtest 'Fortran' => sub {

  plan skip_all => 'Test requires Fortran compiler'
    unless FFI::Build::Platform->which(FFI::Build::Platform->for);
  
  plan skip_all => 'Test requires FFI::Platypus::Lang::Fortran'
    unless eval { require FFI::Platypus::Lang::Fortran };
  

  my $lib = FFI::Build::Library->new('foo', 
    dir       => tempdir( "tmpbuild.XXXXXX", DIR => 'corpus/ffi_build_library/project-fortran' ),
    buildname => "tmpbuild.$$.@{[ time ]}",
    verbose   => 1,
  );
  
  $lib->source('corpus/ffi_build_library/project-fortran/add*.f*');
  note "$_" for $lib->source;

  my($out, $dll, $error) = capture_merged {
    my $dll = eval { $lib->build };
    ($dll, $@);
  };

  ok $error eq '', 'no error';

  if($error)
  {
    diag $out;
    return;
  }
  else
  {
    note $out;
  }
  
  my $ffi = FFI::Platypus->new;
  $ffi->lang('Fortran');
  $ffi->lib($dll);

  is(
    $ffi->function( add1 => [ 'integer*', 'integer*' ] => 'integer' )->call(\1,\2),
    3,
    'FORTRAN 77',
  );

  is(
    $ffi->function( add2 => [ 'integer*', 'integer*' ] => 'integer' )->call(\1,\2),
    3,
    'Fortran 90',
  );
  
  is(
    $ffi->function( add3 => [ 'integer*', 'integer*' ] => 'integer' )->call(\1,\2),
    3,
    'Fortran 95',
  );
  
  cleanup(
    $lib->file->dirname,
    File::Spec->catdir(qw( corpus ffi_build_library project-fortran ), $lib->buildname)
  );

};

done_testing;
