package App::dbinfo;

# AUTHORITY
# DATE
# DIST
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

our %args_common_dbi = (
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

our %args_common_sqlite = (
    dbpath => {
        schema => 'filename*',
        tags => ['connection', 'common'],
        pos => 0,
    },
);

our %args_rels_common = (
    'req_one&' => [
        [qw/dsn dbh/],
    ],
);

our %arg_table = (
    table => {
        summary => 'Table name',
        schema => 'str*',
        req => 1,
        pos => 1,
    },
);

our %arg1opt_table = (
    table => {
        summary => 'Table name',
        schema => 'str*',
        pos => 1,
    },
);

our %arg_detail = (
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
        %args_common_dbi,
        # XXX detail
    },
    args_rels => {
        %args_rels_common,
    },
};
sub list_tables {
    require DBIx::Util::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    return [200, "OK", [
            DBIx::Util::Schema::list_tables($dbh)]];
}

$SPEC{list_sqlite_tables} = {
    v => 1.1,
    summary => 'List tables in the SQLite database',
    args => {
        %args_common_sqlite,
    },
    args_rels => {
    },
};
sub list_sqlite_tables {
    my %args = @_;
    my $dsn; $dsn = "dbi:SQLite:dbname=".delete($args{dbpath}) if defined $args{dbpath};
    list_tables(
        dsn => $dsn,
        %args
    );
}

$SPEC{list_columns} = {
    v => 1.1,
    summary => 'List columns of a table',
    args => {
        %args_common_dbi,
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
    require DBIx::Util::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    my $ltres = list_tables(%args);
    return [500, "Can't list tables: $ltres->[0] - $ltres->[1]"]
        unless $ltres->[0] == 200;
    my $tables = $ltres->[2];
    #my $tables_wo_schema = [map {my $n=$_; $n=~s/.+\.//; $n} @$tables];
    #return [404, "No such table '$args{table}'"]
    #    unless grep { $args{table} eq $_ } (@$tables, @$tables_wo_schema);
    return [404, "No such table '$args{table}'"]
        unless grep { $args{table} eq $_ } @$tables;

    my @cols = DBIx::Util::Schema::list_columns($dbh, $args{table});
    @cols = map { $_->{COLUMN_NAME} } @cols unless $args{detail};
    return [200, "OK", \@cols];
}

$SPEC{list_sqlite_columns} = {
    v => 1.1,
    summary => 'List columns of a SQLite database table',
    args => {
        %args_common_sqlite,
        %arg_table,
        %arg_detail,
    },
    args_rels => {
    },
    examples => [
        {
            args => {dbpath=>'/tmp/test.db', table=>'main.table1'},
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub list_sqlite_columns {
    my %args = @_;
    my $dsn; $dsn = "dbi:SQLite:dbname=".delete($args{dbpath}) if defined $args{dbpath};
    list_columns(
        dsn => $dsn,
        %args
    );
}

our %args_dump_table = (
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
            #'x.perl.coerce_rules'=>['From_str::comma_sep'],
        }],
        cmdline_aliases => {C=>{}},
    },
    include_columns => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'include_column',
        schema => ['array*', {
            of=>'str*',
            #'x.perl.coerce_rules'=>['From_str::comma_sep'],
        }],
        cmdline_aliases => {c=>{}},
    },
    wheres => {
        summary => 'Add WHERE clause',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'where',
        schema => ['array*', {
            of=>'str*',
        }],
        cmdline_aliases => {w=>{}},
    },
    limit_number => {
        schema => 'uint*',
        cmdline_aliases => {n=>{}},
    },
    limit_offset => {
        schema => 'uint*',
        cmdline_aliases => {o=>{}},
    },
);

$SPEC{dump_table} = {
    v => 1.1,
    summary => 'Dump table into various formats',
    args => {
        %args_common_dbi,
        %arg_table,
        %args_dump_table,
    },
    args_rels => {
        %args_rels_common,
    },
    result => {
        schema => 'str*',
    },
    examples => [
        {
            argv => [qw/table1/],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Only include specified columns',
            argv => [qw/table2 -c col1 -c col2/],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Exclude some columns',
            argv => [qw/table3 -C col1 -C col2/],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Select some rows',
            argv => ['table4', '-w', q(name LIKE 'John*'), '-n', 10],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub dump_table {
    my %args = @_;
    my $table = $args{table};
    my $is_hash = $args{row_format} eq 'array' ? 0:1;

    # let's ignore schema for now
    $table =~ s/.+\.//;

    $is_hash++ if $args{exclude_columns} && @{$args{exclude_columns}};

    my $dbh = _connect(\%args);

    my $col_term = "*";
    if ($args{include_columns} && @{$args{include_columns}}) {
        $col_term = join(",", map {$dbh->quote_identifier($_)} @{$args{include_columns}});
    }

    my $wheres = $args{wheres};
    my $sql = join(
        "",
        "SELECT $col_term FROM ", $dbh->quote_identifier($table),
        ($args{wheres} && @{$args{wheres}} ?
             " WHERE ".join(" AND ", @{$args{wheres}}) : ""),
        # XXX what about database that don't support LIMIT clause?
        (defined $args{limit_offset} ? " LIMIT $args{limit_offset},".($args{limit_number} // "-1") :
             defined $args{limit_number} ? " LIMIT $args{limit_number}" : ""),
    );

    my $sth = $dbh->prepare($sql);
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

    [200, "OK", $code_get_row, {stream=>1}];
}

$SPEC{dump_sqlite_table} = {
    v => 1.1,
    summary => 'Dump SQLite table into various formats',
    args => {
        %args_common_sqlite,
        %arg_table,
        %args_dump_table,
    },
    args_rels => {
    },
    result => {
        schema => 'str*',
    },
    examples => [
    ],
};
sub dump_sqlite_table {
    my %args = @_;
    my $dsn; $dsn = "dbi:SQLite:dbname=".delete($args{dbpath}) if defined $args{dbpath};
    dump_table(
        dsn => $dsn,
        %args
    );
}

$SPEC{list_indexes} = {
    v => 1.1,
    summary => 'List database indexes',
    args => {
        %args_common_dbi,
        %arg1opt_table,
    },
    args_rels => {
        %args_rels_common,
    },
};
sub list_indexes {
    require DBIx::Util::Schema;

    my %args = @_;

    my $dbh = _connect(\%args);

    [200, "OK", DBIx::Util::Schema::list_indexes($dbh, $args{table})];
}

$SPEC{list_sqlite_indexes} = {
    v => 1.1,
    summary => 'List SQLite table indexes',
    args => {
        %args_common_sqlite,
        %arg1opt_table,
    },
    args_rels => {
    },
};
sub list_sqlite_indexes {
    my %args = @_;
    my $dsn; $dsn = "dbi:SQLite:dbname=".delete($args{dbpath}) if defined $args{dbpath};
    list_indexes(
        dsn => $dsn,
        %args,
    );
}

1;
#ABSTRACT:

=head1 SYNOPSIS

See included scripts L<dbinfo>, L<dbinfo-sqlite>, ...


=head1 SEE ALSO

L<DBI>

L<diffdb>, L<diffdb-sqlite>, ... (from L<App::diffdb>)
