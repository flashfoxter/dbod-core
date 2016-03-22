# Copyright (C) 2015, CERN
# This software is distributed under the terms of the GNU General Public
# Licence version 3 (GPL Version 3), copied verbatim in the file "LICENSE".
# In applying this license, CERN does not waive the privileges and immunities
# granted to it by virtue of its status as Intergovernmental Organization
# or submit itself to any jurisdiction.

package DBOD::Runtime;

use strict;
use warnings;

our $VERSION = 0.68;

use Moose;
with 'MooseX::Log::Log4perl';

use Try::Tiny;
use IPC::Run qw(run timeout);
use Net::OpenSSH;
use Data::Dumper;
use File::Temp;
use File::Copy;
use Time::Local;
use Time::localtime;
use autodie qw(:io);

sub run_cmd {
    my $self = shift;
    my %args = @_;
    # Using named parameters, but unpacking for clarity and usability
    my $cmd_str = $args{cmd};
    my $timeout = $args{timeout};
    my $devnull = '/dev/null';
    my $output_ref = ( defined ($args{output}) ? $args{output}: \$devnull );
    my @cmd = split ' ', $cmd_str ;
    my ($err, $return_code);
    try {
        if (defined $timeout) {
            $self->log->debug("Executing ${cmd_str} with timeout: ${timeout}");
            run \@cmd, ,'>', $output_ref, '2>', \$err, (my $t = timeout $timeout);
        }
        else {
            $self->log->debug("Executing ${cmd_str}");
            run \@cmd, ,'>', $output_ref, '2>', \$err;
        }
        # If the command executed succesfully we return its exit code
        $self->log->debug("${cmd_str} stdout: " . $$output_ref);
        $self->log->debug("${cmd_str} return code: " . $?);
        $return_code = $?;
    } 
    catch {
        if ($_ =~ m{^IPC::Run: .*timeout}x) {
            # Timeout exception
            $self->log->error("Timeout exception: " . $_);
            $self->log->error("CMD stderr: " . $err);
            return;
        }
        else {
            # Other type of exception ocurred
            $self->log->error("Exception found: " . $_);
            if (defined $err) {
                $self->log->error( "CMD stderr: " . $err );
            }
            return;
        }
    };
    return scalar $return_code;
}

sub mywait {
    my ($self, $method, @params) = @_;
    my $result;
    $self->log->debug( "Calling $method with @params until obtaining results");
    $result= $method->(@params);
    my $time = 1.0;
    while (! defined $result) {
        $self->log->debug( "Received: $result. Waiting $time seconds" );
        sleep $time;
        $time = $time * 2;
        $result = $method->(@params);
    }
    $self->log->debug($result);
    return $result;
}

sub result_code{
    my ($self, $log) = @_;
    my @lines = split(m{\n}x, $log);
    my $code = undef;
    foreach (@lines){
        if ( $_ =~ m{\[(\d)\]}x ){
            $code = $1;
            $self->log->debug('Found return code: ' . $code);
        }
    }
    if (defined $code){
        return scalar int($code);
    }
    else{
        # If the command doesn't return any result code, we take it as bad
        return scalar 1;
    }
}

sub ssh {
    # uncoverable subroutine
    my ($self, $arg_ref) = @_;
    # Using named parameters, but unpacking for clarity and usability
    my $user = $arg_ref->{user};
    my $host = $arg_ref->{host};
    my $cmd = $arg_ref->{cmd};
    my $ssh;
    $self->log->debug("Opening SSH connection ${user}\@${host}");
    $ssh = Net::OpenSSH->new("$user\@$host",
        password => $arg_ref->{password},
        master_stdout_discard => 0,
        master_stderr_discard => 1);
    if ($ssh->error) {
        $self->log->error("SSH connection error: " . $ssh->error);
        return;
    }    
    $self->log->debug("Executing SSH ${cmd} at ${host}");
    my($stdout, $stderr) = $ssh->capture2({timeout => 60 }, $cmd); 
    if ($ssh->error) {
        $self->log->error("SSH Error: " . $ssh->error);
        $self->log->error("SSH Stdout: " . $stdout);
        $self->log->error("SSH Stderr: " . $stderr);
        return;
    }
    return scalar $stdout;
}

sub wait_until_file_exist {
    my ($self, $timeout, $filename) = @_;
    my $poll_interval = 1; # seconds
    $self->log->debug('Waiting for creation of ' . $filename);
    until ((-e $filename) || ($timeout <= 0))
    {
        $timeout -= $poll_interval;
        sleep $poll_interval;
    }
    return scalar ( -e $filename );
}

#@deprecated To be substutituted by run_cmd
# Using it as interface to maintain the inverted logic for error handling
# until the required changes are made in the action scripts
sub run_str {
    my($self, $cmd, $output_ref, $fake, $text) = @_;
    my $rc = $self->run_cmd(cmd => $cmd, output => $output_ref);
    if ($rc != 0) {
        $self->log->error(" $cmd failed with return code: <$rc>");
        return 0; #error
    } else {
        return 1; #ok
    }
}

# We maintain the method to keep compatibility with current calls
sub get_instance_version {
    my($self, $version) = @_;
    $version =~ tr/\.//d;
    $self->log->debug('Processed version' . $version);
    return $version;
}

sub read_file {
    my ($self, $file) = @_;
    $self->log->info("Reading file: <$file>");
    try {
        open my $F, '<', $file;
        my (@text) = <$F>;
        close($F);
        return @text;
    } catch {
        $self->log->error( "Error: $_" );
        return;
    };
}

sub write_file_arr {
    my ($self, $file, $text) = @_;
    $self->log->info("Writing file: <$file> # of lines: " . scalar(@$text) );
    try {
        open my $F, '>', $file;
        foreach (@$text) {
            print $F $_;
        }
        close($F);
        return;
    } catch {
        $self->log->error( "Error: $_" );
        return;
    };
}

#it expects three arguments, otherwise returns undef
#it returns a full patch <dir>/<filename>
sub get_temp_filename {
    my($self, $template,$directory,$suffix)=@_;
    if (! defined $template || ! defined $directory || ! defined $suffix) {
        $self->log->debug("some variable missing, please check ");
        return;
    }
    $self->log->debug("template: <$template> directory: <$directory> suffix: <$suffix> ");
    my $fh = File::Temp->new(
        TEMPLATE => $template,
        DIR      => $directory,
        SUFFIX   => $suffix,
        UNLINK   => 1,
    );

    #it returns a full patch <dir>/<filename>
    return $fh->filename;
}

1;
