package FFI::Build::Library;

use strict;
use warnings;
use 5.008001;
use FFI::Build::File::Library;
use Carp ();
use File::Glob ();
use File::Basename ();
use List::Util 1.45 ();
use Capture::Tiny ();
use Text::ParseWords ();

# ABSTRACT: Library builder class for native dynamic libraries
# VERSION

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONSTRUCTOR

=head2 new

=cut

sub _native_name
{
  my($self, $name) = @_;
  join '', $self->platform->library_prefix, $name, $self->platform->library_suffix;
}

sub new
{
  my($class, $name, %args) = @_;

  Carp::croak "name is required" unless defined $name;

  my $self = bless {
    source => [],
    cflags => [],
    libs   => [],
  }, $class;
  
  my $platform  = $self->{platform}  = FFI::Build::Platform->default;
  my $file      = $self->{file}      = $args{file} || FFI::Build::File::Library->new([$args{dir} || '.', $self->_native_name($name)], platform => $self->platform);
  my $buildname = $self->{buildname} = $args{buildname} || '_build';
  my $verbose   = $self->{verbose}   = $args{verbose};

  if(defined $args{cflags})
  {
    $self->{cflags} = ref $args{cflags} ? [ @{ $args{cflags} } ]: [Text::ParseWords::shellwords($args{cflags})];
  }
  
  if(defined $args{libs})
  {
    $self->{libs} = ref $args{libs} ? [ @{ $args{libs} } ] : [Text::ParseWords::shellwords($args{libs})];
  }
  
  $self;
}

=head1 METHODS

=head2 dir

=head2 buildname

=head2 file

=head2 platform

=head2 verbose

=head2 cflags

=head2 libs

=cut

sub buildname { shift->{buildname} }
sub file      { shift->{file}      }
sub platform  { shift->{platform}  }
sub verbose   { shift->{verbose}   }
sub cflags    { shift->{cflags}    }
sub libs      { shift->{libs}      }

=head2 source

=cut

my @file_classes;
sub _file_classes
{
  unless(@file_classes)
  {

    foreach my $inc (@INC)
    {
      push @file_classes,
        map { $_ =~ s/\.pm$//; "FFI::Build::File::$_" }
        grep !/^Base\.pm$/,
        map { File::Basename::basename($_) } 
        File::Glob::bsd_glob(
          File::Spec->catfile($inc, 'FFI', 'Build', 'File', '*.pm')
        );
    }

    # also anything already loaded, that might not be in the
    # @INC path (for testing ususally)
    push @file_classes,
      map { s/::$//; "FFI::Build::File::$_" }
      grep !/Base::/,
      grep /::$/,
      keys %{FFI::Build::File::};

    @file_classes = List::Util::uniq(@file_classes);
    foreach my $class (@file_classes)
    {
      next if(eval { $class->can('new') });
      my $pm = $class . ".pm";
      $pm =~ s/::/\//g;
      require $pm;
    }
  }
  @file_classes;
}

=head2 source

=cut

sub source
{
  my($self, @file_spec) = @_;
  
  foreach my $file_spec (@file_spec)
  {
    my @paths = File::Glob::bsd_glob($file_spec);
path:
    foreach my $path (@paths)
    {
      foreach my $class (_file_classes)
      {
        foreach my $regex ($class->accept_suffix)
        {
          if($path =~ $regex)
          {
            push @{ $self->{source} }, $class->new($path, platform => $self->platform, library => $self);
            next path;
          }
        }
      }
      Carp::croak("Unknown file type: $path");
    }
  }
  
  @{ $self->{source} };
}

=head2 build

=cut

sub build
{
  my($self) = @_;

  my @objects;
  
  foreach my $source ($self->source)
  {
    my $output;
    while(my $next = $source->build)
    {
      $output = $source = $next;
    }
    push @objects, $output;
  }
  
  my @cmd = (
    $self->platform->ld,
    $self->platform->ldflags,
    @{ $self->libs },
    $self->platform->extra_system_lib,
    (map { "$_" } @objects),
    -o => $self->file->path,
  );
  
  my($out, $exit) = Capture::Tiny::capture_merged(sub {
    $DB::single = 1;
    print "+ @cmd\n";
    system @cmd;
  });
  
  if($exit || !-f $self->file->path)
  {
    print $out;
    die "error building @{[ $self->file->path ]} from @objects";
  }
  elsif($self->verbose)
  {
    print $out;
  }
  
  $self->file;
}

1;