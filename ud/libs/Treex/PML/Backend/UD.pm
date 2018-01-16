package Treex::PML::Backend::UD;

=head1 Treex::PML::Backend::UD

=cut

use warnings;
use strict;

use Treex::PML::IO qw{ open_backend close_backend };

sub test {
    my ($filename, $encoding) = @_;
    open my $in, '<', $filename or die "$filename: $!";
    my $first_line = <$in>;

    return 1 if $first_line =~ /^# (?:new(?:doc|par)\s+id|sent_id|text) = /;
    return
}


sub read {
    my ($fh, $doc) = @_;
    my $schema = 'Treex::PML::Factory'->createPMLSchema({
        filename => 'ud_schema.xml',
        use_resources => 1});
    $doc->changeMetaData('schema', $schema);

    my $root;
    while (<$fh>) {
        chomp;
        if (/^#/ && ! $root) {
            $root = 'Treex::PML::Factory'->createTypedNode(
                    'ud.sent.type', $schema, {}
            );
        }

        if (/^#\s*sent_id\s=\s*(\S+)/) {
            my $sent_id = $1;
            substr $sent_id, 0, 0, 'PML-' if $sent_id =~ /^(?:[0-9]|PML-)/;
            $root->{id} = $sent_id;
            $doc->append_tree($root, $doc->lastTreeNo);

        } elsif (/^#\s*text\s*=\s*(.*)/) {
            $root->{text} = $1;

        } elsif (/^$/) {
            _create_structure($root);
            undef $root;

        } elsif (/^#\s+new(doc|par)(?:\s+id = (.*))?/) {
            $root->{$1} = $2;

        } elsif (/^#/) {
            $root->{comment} = 'Treex::PML::Factory'->createList([
                @{ $root->{comment} || [] }, substr $_, 1 ]);

        } else {
            my ($n, $form, $lemma, $upos, $xpos, $feats, $head, $deprel,
                $deps, $misc) = map '_' eq $_ ? undef : $_, split /\t/;
            next if $n =~ /-/;  # TODO: multiword

            $feats = { split /=|\|/, ($feats // "") };
            $misc = [ split /\|/, ($misc // "") ];
            $deps = [ map {
                my ($parent, $func) = split /:/;
                'Treex::PML::Factory'->createContainer($parent,
                                                       {func => $func});
            } split /\|/, ($deps // "") ];

            'Treex::PML::Factory'->createTypedNode('ud.node.type', $schema,
                {
                    form    => $form,
                    lemma   => $lemma,
                    ord     => $n,
                    deprel  => $deprel,
                    upostag => $upos,
                    xpostag => $xpos,
                    feats   => $feats,
                    deps    => 'Treex::PML::Factory'->createList($deps),
                    misc    => 'Treex::PML::Factory'->createList($misc),
                    head    => $head}
                )->paste_on($root, 'ord');
        }
    }
    if ($root) {
        _create_structure($root);
        warn "Emtpy line missing at the end of input\n";
    }
}


sub write {
    my ($fh, $doc) = @_;
    for my $root ($doc->trees) {
        _serialize_doc_and_par($root, $fh);

        $root->{id} =~ s/^PML-//;
        print {$fh} "# sent_id = ", $root->{id}, "\n";
        print {$fh} "# text = ", $root->{text}, "\n" if exists $root->{text};
        print {$fh} map "#$_\n", @{ $root->{comment} };
        for my $node (sort { $a->{ord} <=> $b->{ord} } $root->descendants) {
            print {$fh} join "\t",
                @$node{qw{ ord form lemma upostag xpostag }},
                join('|',
                     map "$_=$node->{feats}{$_}",
                     sort { lc $a cmp lc $b }
                     keys %{ $node->{feats} }) || '_',
                $node->parent->{ord} || '0',
                $node->{deprel} || '_',
                _serialize_deps($node->{deps}),
                join('|', @{ $node->{misc} }) || '_'
            ;
            print {$fh} "\n";
        }
        print {$fh} "\n";
    }
    return 1
}


sub _serialize_doc_and_par {
    my ($root, $fh) = @_;
    for my $attr (qw( doc par )) {
        if (exists $root->{$attr}) {
            print {$fh} "# new$attr";
            print {$fh} ' id = ', $root->{$attr} if length $root->{$attr};
            print {$fh} "\n";
        };
    }
}


sub _serialize_deps {
    my ($deps) = @_;
    return '_' unless @$deps;
    return join '|',
           map "$_->{'#content'}:$_->{func}",
           sort { $a->{'#content'} <=> $b->{'#content'} }
           @$deps;
}


sub _create_structure {
    my ($root) = @_;
    my %ord = map +($_->{ord} => $_), $root->children;
    for my $node ($root->children) {
        $node->cut->paste_on($ord{ $node->{head} || $root } || $root, 'ord');
    }
}

__PACKAGE__
