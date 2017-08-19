package App::dbinfo;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Get/extract information from database',
};

my %args_common = (
    dsn => {
        summary => 'DBI data source, '.
            'e.g. "dbi:SQLite:dbname=/path/to/db.db"',
        schema => 'str*',
        tags => ['connection', 'common'],
        pos => 0,
    },
    user => {
        schema => 'str*',
        cmdline_aliases => {u=>{}},
        tags => ['connection', 'common'],
    },
    password => {
        schema => 'str*',
        cmdline_aliases => {p=>{}},
        tags => ['connection', 'common'],
        description => <<'_',

You might want to specify this parameter in a configuration file instead of
directly as command-line option.

_
    },
    dbh => {
        summary => 'Alternative to specifying dsn/user/password (from Perl)',
        schema => 'obj*',
        tags => ['connection', 'common', 'hidden-cli'],
    },
);

my %args_rels_common = (
    'req_one&' => [
        [qw/dsn dbh/],
    ],
);

my %arg_table = (
    table => {
        summary => 'Table name',
        schema => 'str*',
        req => 1,
        pos => 1,
    },
);

my %arg_detail = (
    detail => {
        summary => 'Show detailed information per record',
        schema => 'bool*',
        cmdline_aliases => {l=>{}},
    },
);

sub __json_encode {
    state $json = do {
        require JSON::MaybeXS;
        JSON::MaybeXS->new->canonical(1);
    };
    $json->encode(shift);
}

sub _connect {
    require DBI;

    my $args = shift;

    return $args->{dbh} if $args->{dbh};
    DBI->connect($args->{dsn}, $args->{user}, $args->{password},
                 {RaiseError=>1});
}

$SPEC{list_tables} = {
    v => 1.1,
    summary => 'List tables in the database',
    args => {
        %args_common,
    },
    args_rels => {
        %args_rels_common,
    },
};
sub list_tables {
    require DBIx::Diff::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    return [200, "OK", [
            DBIx::Diff::Schema::_list_tables($dbh)]];
}

$SPEC{list_columns} = {
    v => 1.1,
    summary => 'List columns of a table',
    args => {
        %args_common,
        %arg_table,
        %arg_detail,
    },
    args_rels => {
        %args_rels_common,
    },
    examples => [
        {
            args => {dsn=>'dbi:SQLite:database=/tmp/test.db', table=>'main.table1'},
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub list_columns {
    require DBIx::Diff::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    # XXX check table exists

    my @cols = DBIx::Diff::Schema::_list_columns($dbh, $args{table});
    @cols = map { $_->{COLUMN_NAME} } @cols unless $args{detail};
    return [200, "OK", \@cols];
}

$SPEC{dump_table} = {
    v => 1.1,
    summary => 'Dump table into various formats',
    args => {
        %args_common,
        %arg_table,
        row_format => {
            schema => ['str*', in=>['array', 'hash']],
            default => 'hash',
            cmdline_aliases => {
                array => { summary => 'Shortcut for --row-format=array', is_flag=>1, code => sub { $_[0]{row_format} = 'array' } },
                a     => { summary => 'Shortcut for --row-format=array', is_flag=>1, code => sub { $_[0]{row_format} = 'array' } },
            },
        },
        exclude_columns => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'exclude_column',
            schema => ['array*', {
                of=>'str*',
                #'x.perl.coerce_rules'=>['str_comma_sep'],
            }],
            cmdline_aliases => {C=>{}},
        },
        include_columns => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'include_column',
            schema => ['array*', {
                of=>'str*',
                #'x.perl.coerce_rules'=>['str_comma_sep'],
            }],
            cmdline_aliases => {c=>{}},
        },
    },
    args_rels => {
        %args_rels_common,
    },
    result => {
        schema => 'str*',
        stream => 1,
    },
};
sub dump_table {
    require DBIx::Diff::Schema;

    my %args = @_;
    my $table = $args{table};
    my $is_hash = $args{row_format} eq 'array' ? 0:1;

    $is_hash++ if $args{exclude_columns} && @{$args{exclude_columns}};

    my $col_term = "*";
    if ($args{include_columns} && @{$args{include_columns}}) {
        $col_term = join(",", map {qq("$_")} @{$args{include_columns}});
    }

    my $dbh = _connect(\%args);

    my $sth = $dbh->prepare("SELECT $col_term FROM \"$table\"");
    $sth->execute;

    my $code_get_row = sub {
        my $row;
        if ($is_hash) {
            $row = $sth->fetchrow_hashref;
            return undef unless $row;
            if ($args{exclude_columns} && @{$args{exclude_columns}}) {
                for (@{ $args{exclude_columns} }) {
                    delete $row->{$_};
                }
            }
        } else {
            $row = $sth->fetchrow_arrayref;
            return undef unless $row;
        }
        __json_encode($row);
    };

    [200, "OK", $code_get_row];
}


1;
#ABSTRACT:

=head1 SYNOPSIS

See included script L<dbinfo>.


=head1 SEE ALSO

L<DBI>

L<App::diffdb>
