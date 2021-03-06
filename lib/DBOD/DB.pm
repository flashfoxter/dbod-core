# Copyright (C) 2015, CERN
# This software is distributed under the terms of the GNU General Public
# Licence version 3 (GPL Version 3), copied verbatim in the file "LICENSE".
# In applying this license, CERN does not waive the privileges and immunities
# granted to it by virtue of its status as Intergovernmental Organization
# or submit itself to any jurisdiction.

package DBOD::DB;

use strict;
use warnings;

use Moose;
with 'MooseX::Log::Log4perl';
with 'MooseX::Role::DBIx::Connector' => {
    connection_name => 'db',
};

our ($VERSION);
$VERSION     = 0.67;

use Data::Dumper;
use Try::Tiny;

sub execute_sql_file {
    my ($self, $filename) = @_;
    open my $fh, '<', $filename or do {
        $self->log->error("Can't open SQL File for reading: $!");
        return;
        };
    my @statements = <$fh>;
    close($fh);
    try {
        # local $/=';';
        foreach my $statement (@statements) {
            $self->log->debug("Executing: ${statement}");
            $self->db_conn->dbh->do($statement);
        }
        return 0;
    } catch {
        $self->log->error(
            sprintf("An error ocurred executing SQL file:\n%s:%s", 
                $self->db_conn->dbh->err,
                $self->db_conn->dbh->errstr));
        return $self->db_conn->dbh->err;
    };
    return; # Needed because Perlcritic doesn't support Try:Tiny
}

# Perlcritic gives a severity 4 warning related to the following two methods,
# as they are homonyms to Perl builtin function. As they are object methods
# which need to be used for an instance, we consider there is no scope
# overlapping.

sub select {
    my ($self, $statement, $bind_values) = @_;
    $self->log->debug("Running SQL statement: " . $statement);
    my $rows = try {
        if (defined $bind_values) {
            return $self->db_conn->dbh->selectall_arrayref($statement, @{$bind_values});
            }
        else {
            return $self->db_conn->dbh->selectall_arrayref($statement);
        }
    } catch {
        $self->log->error(
            sprintf("An error ocurred executing SQL statement:\n%s:%s", 
                $self->db_conn->dbh->err,
                $self->db_conn->dbh->errstr));
        return;
    };
    return $rows;
}

 
sub do {
    my ($self, $statement, $bind_values) = @_;
    $self->log->debug("Running SQL statement: " . $statement);
    my $rows = try {
        if (defined $bind_values) {
            return $self->db_conn->dbh->do($statement, undef, @{$bind_values});
            }
        else {
            return $self->db_conn->dbh->do($statement,);
        }
    } catch {
        $self->log->error(
            sprintf("An error ocurred executing SQL sttatement:\n%s:%s", 
                $self->db_conn->dbh->err,
                $self->db_conn->dbh->errstr));
        return;
    };
    return $rows;
}

1;
