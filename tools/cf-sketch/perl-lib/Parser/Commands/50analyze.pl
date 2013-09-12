#
# analyze command. Internal use mostly.
#
# CFEngine AS, August 2013

use Util;

%COMMANDS =
 (
  'analyze' =>
  [
   [
    'analyze [-table] [REGEXP]',
    'Produce some information about the structure of all sketches matching REGEXP. If REGEXP is omitted or "all", then all sketches are analyzed. By default the result is printed in CSV format. If -table is specified, it is printed in Redmine wiki table format',
    '(?:(-table)\b\s*)?(.*)'
   ]
  ]
 );

######################################################################

sub command_analyze
{
    my $wiki_out = shift;
    my $regex = shift;

    my @fields = qw(
                       string_p
                       boolean_p
                       list_p
                       array_p
                       environment_p
                       metadata_p
                       bundle_options_p
                       return_p
                       enterprise_compatible
                       namespace_decl
                       multiple_entry_points
                       is_library
                  );

    # Pending fields:
    #                       has_activation_id_decl
    #                       has_activation_id_use

    $regex = "." if ($regex eq 'all' or !$regex);
    my $err = Util::check_regex($regex);
    if ($err)
    {
        Util::error($err);
    }
    else
    {
        # %result is indexed by sketch name. Each element contains fields
        # as per @fields, with true/false values for each.
        my %result = ();

        ($success, $result) = main::api_interaction({
                                                     describe => 1,
                                                     search => $regex,
                                                    });
        my $list = Util::hashref_search($result, 'data', 'search');
        foreach my $repo (sort keys %$list)
        {
            my $repo_obj = $Config{dcapi}->load_repo($repo);
            foreach my $sketch (sort keys %{$list->{$repo}})
            {
                my $sketch_obj = $repo_obj->find_sketch($sketch);
                my $meta = Util::hashref_search($list->{$repo}->{$sketch}, qw/metadata/);
                my $api = Util::hashref_search($list->{$repo}->{$sketch}, qw/api/);

                # Initialize record with false (undef) values
                my %f=();
                @f{@fields}=();

                # Multiple entry points or a library sketch?
                $f{multiple_entry_points} = (scalar(keys %$api) > 1);
                $f{is_library} = (scalar(keys %$api) == 0);

                # Parameter types used
                foreach my $bundle (keys %$api)
                {
                    foreach my $p (@{$api->{$bundle}})
                    {
                        $f{$p->{type}."_p"} = 1;
                    }
                }

                # Tagged as enterprise_compatible? This needs Perl 5.10+
                $f{enterprise_compatible} = ('enterprise_compatible' ~~ @{$meta->{tags}});

                # We don't need to parse anything if it's a library
                unless ($f{is_library})
                {
                    # Now we read in the file for parsing. For now this only really
                    # works with a local sketch repository. We load only the first
                    # file from the sketch interface declaration.
                    my $file = $sketch_obj->location . '/' . $list->{$repo}->{$sketch}->{interface}->[0];
                    my $json = Util::parse_cf_file($Config{dcapi}, $file);
                    if (!defined($json))
                    {
                        Util::error("Something went wrong reading file '$file' - skipping.\n");
                    }
                    else
                    {
                        # Find if there's a namespace declaration
                        foreach my $body (@{$json->{bodies}})
                        {
                            if ($body->{bodyType} eq 'file' &&
                                $body->{name} eq 'control') {
                                foreach my $c (@{$body->{contexts}})
                                {
                                    if (Util::hashref_search($c, 'attributes', { lval => 'namespace' }))
                                    {
                                        $f{namespace_decl} = 1;
                                    }
                                }
                            }
                        }
                    }
                }

                # Assign the results into the appropriate record
                $result{$sketch}= \%f;
            }
        }
        # Print the results
        # First the header
        print_row($wiki_out ? "wiki_hdr" : "csv", 'sketch_name', @fields);
        foreach my $s (sort keys %result)
        {
            print_row($wiki_out ? "wiki" : "csv", $s, map { $result{$s}->{$_} ? '1' : '' } @fields);
        }
    }
}

sub print_row
{
    my $format = shift;
    if ($format eq 'wiki')
    {
        print "| ".join(" | ", @_)." |\n";
    }
    elsif ($format eq 'wiki_hdr')
    {
        print "|_. ".join(" |_. ", @_)." |\n";
    }
    else
    {
        # Default CSV
        print join(',', @_)."\n";
    }
}
