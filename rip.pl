#! /usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;

my @drives = [];
my $debug = $ENV{DEBUG};

print "About to scan drive...\n";
my @scan_return_raw = `HandBrakeCLI -v -i /dev/sr0 -t 0 2>&1`;
print "Got " . scalar(@scan_return_raw) . " lines from scan.\n\n";

print "Chomping results...\n";
chomp @scan_return_raw;
print "Chomp done.\n\n";

print "Getting Title & Serial from results...\n";
my @titles = grep(/DVD Title:/, @scan_return_raw);
my @serials = grep(/DVD Serial Number:/, @scan_return_raw);
print "WARNING: Could not find title in output." if scalar @titles < 1;
print "WARNING: Found many titles in output." if scalar @titles > 1;
print "WARNING: Could not find serial in output." if scalar @serials < 1;
print "WARNING: Found many serials in output." if scalar @serials > 1;
print "Title (raw): " . $titles[0] . "\n" if $debug;
$titles[0] =~ /DVD Title: (.*?)$/;
my $title = $1;
print "Title (processed): " . $title . "\n" if $debug;
print "Serial (raw): " . $serials[0] . "\n" if $debug;
$serials[0] =~ /DVD Serial Number: (.*?)$/;
my $serial = $1;
print "Serial (processed): " . $serial . "\n" if $debug;
print "Got Serial [$serial] and Title [$title]\n\n";

print "Stripping out the non-useful data from dump...\n";
my @scan_return_processed = grep(/^\s*\+/, @scan_return_raw);
my $stripped_lines_count = scalar(@scan_return_raw) - scalar(@scan_return_processed);
print "Removed $stripped_lines_count lines of data from the dump.\n\n";

print "Processing response from Handbrake into a hash.\n";
my %disk_titles;
my $title_id;

foreach my $scan_line (@scan_return_processed) {

    # If we've found a "+ title", perform title switching logic. Stash away the title ID so we can use it for upcoming lines.
    if ($scan_line =~ m/\+ title (\d+)/) {
 	print "    Found Title! [" . $scan_line . "]\n";
	$disk_titles{$1} = {"title_id" => $1};
	$disk_titles{$1}->{"raw_title"} = $scan_line;
	$title_id = $1;
    }

    else {

	# Duration
	if ($scan_line =~ m/\s*\+ duration: (\d\d):(\d\d):(\d\d)/) {
	    my ($h, $m, $s) = ($1, $2, $3);
	    print "        Found duration! [" . $scan_line . "]\n";
	    $disk_titles{$title_id}->{"duration_seconds"} = ($h * 3600) + ($m * 60) + $s;
	    $disk_titles{$title_id}->{"raw_duration"} = $scan_line;
	}

	else {
	    if ($debug) {
		print "Warning: Did not parse line: [" . $scan_line . "]\n";
	    }
	}
    }
}
print "Found " . scalar(keys(%disk_titles)) . " titles for transcode.\n\n";

print "Filtering out titles that don't fit within duration windows...\n\n";

print "Processing done!\n\n";
print Dumper \%disk_titles;
