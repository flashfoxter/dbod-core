# Copyright (C) 2015, CERN
# This software is distributed under the terms of the GNU General Public
# Licence version 3 (GPL Version 3), copied verbatim in the file "LICENSE".
# In applying this license, CERN does not waive the privileges and immunities
# granted to it by virtue of its status as Intergovernmental Organization
# or submit itself to any jurisdiction.

package DBOD;

use strict;
use warnings;
use base 'Exporter';
use Readonly;

our ($VERSION, @EXPORT, $ERROR, $OK, $TRUE, $FALSE, %db_type, $db_type);

$VERSION = 0.70;

Readonly $ERROR => 1;
Readonly $OK => 0;
Readonly $TRUE => 1;
Readonly $FALSE => 0;

Readonly %db_type => (
    MYSQL => 'MySQL',
    PG => 'PG',
    InfluxDB => 'InfluxDB',
);

$db_type = \%db_type;

@EXPORT = qw( $ERROR $OK $TRUE $FALSE $db_type);

1;
