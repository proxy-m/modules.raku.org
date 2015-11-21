package DbBuilder;

use strictures 2;

use Data::GUID;
use File::Path             qw/make_path  remove_tree/;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util             qw/slurp  trim/;
use Types::Common::Numeric qw/PositiveNum/;
use Types::Standard        qw/InstanceOf  Str  Bool  Maybe/;

use DbBuilder::Log;
use DbBuilder::Dist;
use ModulesPerl6::Model::BuildStats;
use ModulesPerl6::Model::Dists;

use Moo;
use namespace::clean;

has _app => (
    init_arg => 'app',
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has _db_file => (
    init_arg => 'db_file',
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has _limit => (
    init_arg => 'limit',
    is  => 'ro',
    isa => Maybe[ PositiveNum ],
);

has _logos_dir => (
    init_arg => 'logos_dir',
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has _restart_app => (
    init_arg => 'restart_app',
    is  => 'ro',
    isa => Maybe[ Bool ],
);

has _meta_list => (
    init_arg => 'meta_list',
    is       => 'ro',
    isa      => Str | InstanceOf[qw/Mojo::URL  URI/],
    required => 1,
);

#########################

sub run {
    my $self = shift;

    $self->_prep_dirs;

    my $build_id = Data::GUID->new->as_base64;
    log info => "Starting build $build_id";

    my $m = ModulesPerl6::Model::Dists->new( db_file => $self->db_file );
    $m->add(
        DbBuilder::Dist->new( meta_url => $_, build_id => $build_id )->as_hash
    ) for $self->_meta_list;

    if ( $self->_restart_app ) {
        system $^O eq 'MSWin32'
            ? $self->_app => 'daemon' # hypnotoad is not supported on Win32
            : hypnotoad   => $self->_app;
    }

    $self;
}

#########################

sub _meta_list {
    my $self = shift;
    my $meta_list = $self->_meta_list;

    log info => "Loading META.list from $meta_list";
    my $url = Mojo::URL->new( $meta_list );
    my $raw_data;
    if ( $url->scheme =~ /(ht|f)tps?/i ) {
        log info => '... a URL detected; trying to fetch';
        my $tx = Mojo::UserAgent->new( max_redirects => 10 )->get( $url );

        if ( $tx->success ) { $raw_data = $tx->res->body }
        else {
            my $err = $tx->error;
            log fatal => "$err->{code} response: $err->{message}"
                if $err->{code};
            log fatal => "Connection error: $err->{message}";
        }
    }
    elsif ( -r $meta_list ) {
        log info => '... a file detected; trying to read';
        $raw_data = slurp $meta_list;
    }
    else {
        log fatal => 'Could not figure out how to load META.list. It does '
            . 'not seem to be a URL, but is not a [readable] file either';
    }

    my @metas = grep /\S/, map trim($_), split m{\Q$/\E}, $raw_data;
    log info => 'Found ' . @metas . ' dists';

    return @metas;
}

sub _prep_dirs {
    my $self = shift;
    my $logos_dir = $self->logos_dir;

    log info => "Cleaning up dist logos dir [$logos_dir]";
    remove_tree $logos_dir;
    make_path   $logos_dir => { mode => 0755 };
}

1;

__END__
