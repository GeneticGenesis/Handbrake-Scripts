#! /usr/bin/env perl

use warnings;
use strict;
use Data::Dumper;

my $debug = $ENV{DEBUG};
my $min_duration_seconds = 600;
my $max_duration_seconds = 3600;
my $input_device = '/dev/sr0';

my @titles_to_transcode_for_this_drive = find_and_filter_titles($input_device, $min_duration_seconds, $max_duration_seconds);
print Dumper @titles_to_transcode_for_this_drive;

sub log_info {
    my ($device, $message) = @_;
    my $now = localtime;
    print "[INFO] - [$now] - [$device] - $message\n";
}

sub log_warn {
    my ($device, $message) = @_;
    my $now = localtime;
    print "[WARN] - [$now] - [$device] - $message\n";
}

sub log_debug {
    if ($debug) {
	my ($device, $message) = @_;
	my $now = localtime;
	print "[DEBUG] - [$now] - [$device] - $message\n";
    }
}

sub get_title_from_raw {
    my ($device, @raw) = @_;
    my @titles = grep(/DVD Title:/, @raw);
    log_warn($device, "Could not find title in output.") if scalar @titles < 1;
    log_warn($device, "Found many titles in output.") if scalar @titles > 1;
    log_debug($device, "Title (raw): " . $titles[0]);
    $titles[0] =~ /DVD Title: (.*?)$/;
    my $title = $1;
    log_debug($device, "Title (processed): " . $title);
    return $title;
}

sub get_serial_from_raw {
    my ($device, @raw) = @_;
    my @serials = grep(/DVD Serial Number:/, @raw);
    log_warn($device, "Could not find serial in output.") if scalar @serials < 1;
    log_warn($device, "Found many serials in output.") if scalar @serials > 1;
    log_debug($device, "Serial (raw): " . $serials[0]);
    $serials[0] =~ /DVD Serial Number: (.*?)$/;
    my $serial = $1;
    log_debug($device, "Serial (processed): " . $serial);
    return $serial;
}

sub find_and_filter_titles {
    my ($input_device, $min_duration_seconds, $max_duration_seconds) = @_;

    log_info($input_device, "About to scan $input_device...");
    my @scan_return_raw = `HandBrakeCLI -v -i $input_device -t 0 2>&1`;
    log_info($input_device, "Got " . scalar(@scan_return_raw) . " lines from scan.");

    log_info($input_device, "Chomping results...");
    chomp @scan_return_raw;
    log_info($input_device, "Chomp done.");

    log_info($input_device, "Getting Title & Serial from results...");
    my $title = get_title_from_raw($input_device, @scan_return_raw);
    my $serial = get_serial_from_raw($input_device, @scan_return_raw);
    log_info($input_device, "Got Serial [$serial] and Title [$title]");

    log_info($input_device, "Stripping out the non-useful data from dump...");
    my @scan_return_processed = grep(/^\s*\+/, @scan_return_raw);
    my $stripped_lines_count = scalar(@scan_return_raw) - scalar(@scan_return_processed);
    log_info($input_device, "Removed $stripped_lines_count lines of data from the dump.");

    log_info($input_device, "Processing response from Handbrake into a hash...");
    my %disk_titles;
    my $latest_title_id;

    foreach my $scan_line (@scan_return_processed) {

	# If we've found a "+ title", perform title switching logic. Stash away the title ID so we can use it for upcoming lines.
	if ($scan_line =~ m/\+ title (\d+)/) {
	    log_info($input_device, "    Found Title! [" . $scan_line . "]");
	    $disk_titles{$1} = {"title_id" => $1};
	    $disk_titles{$1}->{"raw_title"} = $scan_line;
	    $latest_title_id = $1;
	}

	else {

	    # Duration
	    if ($scan_line =~ m/\s*\+ duration: (\d\d):(\d\d):(\d\d)/) {
		my ($h, $m, $s) = ($1, $2, $3);
		log_info($input_device, "        Found duration! [" . $scan_line . "]");
		$disk_titles{$latest_title_id}->{"duration_seconds"} = ($h * 3600) + ($m * 60) + $s;
		$disk_titles{$latest_title_id}->{"raw_duration"} = $scan_line;
	    }

	    else {
		log_debug($input_device, "Did not parse line: [" . $scan_line . "]");
	    }
	}
    }
    log_info($input_device, "Found " . scalar(keys(%disk_titles)) . " titles for transcode.");

    log_info($input_device, "Filtering out titles that don't fit within duration windows (Min: $min_duration_seconds | Max: $max_duration_seconds)...");
    my $filtered_count = 0;
    foreach my $title_id (keys(%disk_titles)) {
	log_info($input_device, "    Testing Title: $title_id");
	my $this_title_duration = $disk_titles{$title_id}->{duration_seconds};
	if (($this_title_duration > $min_duration_seconds) and ($this_title_duration < $max_duration_seconds)) {
	    log_info($input_device, "        Will transcode Title: $title_id (Duration: $this_title_duration seconds)");
	}
	else {
	    $filtered_count++;
	    delete $disk_titles{$title_id};
	}
    }
    my $to_transcode_count = scalar(keys(%disk_titles));
    log_info($input_device, "Filtered out $filtered_count titles. Will transcode $to_transcode_count titles.");

    # Last chance to see the disk info objects.
    log_debug($input_device, Dumper \%disk_titles);

    log_info($input_device, "Coercing data into a more sensible (And ordered) format and generating TranscodeRequests...");
    my @transcode_requests;
    my @sorted_title_ids = sort {$a <=> $b} (keys(%disk_titles));
    foreach my $title_id (@sorted_title_ids) {
	my $transcode_request = {'title_id' => $title_id, 'input_drive' => $input_device, 'target_filename' => "$serial-$title-title-$title_id"};  
	push @transcode_requests, $transcode_request;

    }
    log_info($input_device, "Requesting " . scalar @transcode_requests . " TranscodeRequest objects.");
    return @transcode_requests;

}
