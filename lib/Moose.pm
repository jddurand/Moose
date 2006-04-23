
package Moose;

use strict;
use warnings;

our $VERSION = '0.05';

use Scalar::Util 'blessed', 'reftype';
use Carp         'confess';
use Sub::Name    'subname';

use UNIVERSAL::require;
use Sub::Exporter;

use Class::MOP;

use Moose::Meta::Class;
use Moose::Meta::TypeConstraint;
use Moose::Meta::TypeCoercion;
use Moose::Meta::Attribute;

use Moose::Object;
use Moose::Util::TypeConstraints;

{
    my ( $CALLER, %METAS );

    sub _find_meta {
        my $class = $CALLER;

        return $METAS{$class} if exists $METAS{$class};

        # make a subtype for each Moose class
        subtype $class
            => as 'Object'
            => where { $_->isa($class) }
        unless find_type_constraint($class);

        my $meta;
        if ($class->can('meta')) {
            $meta = $class->meta();
            (blessed($meta) && $meta->isa('Moose::Meta::Class'))
                || confess "Whoops, not møøsey enough";
        }
        else {
            $meta = Moose::Meta::Class->initialize($class);
            $meta->add_method('meta' => sub {
                # re-initialize so it inherits properly
                Moose::Meta::Class->initialize($class);
            })
        }

        # make sure they inherit from Moose::Object
        $meta->superclasses('Moose::Object')
           unless $meta->superclasses();

        return $METAS{$class} = $meta;
    }

    my %exports = (
        extends => sub {
            my $meta = _find_meta();
            return subname 'Moose::extends' => sub {
                _load_all_classes(@_);
                $meta->superclasses(@_)
            };
        },
        with => sub {
            my $meta = _find_meta();
            return subname 'Moose::with' => sub {
                my ($role) = @_;
                _load_all_classes($role);
                $role->meta->apply($meta);
            };
        },
        has => sub {
            my $meta = _find_meta();
            return subname 'Moose::has' => sub {
                my ($name, %options) = @_;
                if ($name =~ /^\+(.*)/) {
                    my $inherited_attr = $meta->find_attribute_by_name($1);
                    (defined $inherited_attr)
                        || confess "Could not find an attribute by the name of '$1' to inherit from";
                    #(scalar keys %options == 1 && exists $options{default})
                    #    || confess "Inherited slot specifications can only alter the 'default' option";
                    my $new_attr = $inherited_attr->clone(%options);
                    $meta->add_attribute($new_attr);
                }
                else {
                    if ($options{metaclass}) {
                        _load_all_classes($options{metaclass});
                        $meta->add_attribute($options{metaclass}->new($name, %options));
                    }
                    else {
                        $meta->add_attribute($name, %options);
                    }
                }
            };
        },
        before => sub {
            my $meta = _find_meta();
            return subname 'Moose::before' => sub {
                my $code = pop @_;
                $meta->add_before_method_modifier($_, $code) for @_;
            };
        },
        after => sub {
            my $meta = _find_meta();
            return subname 'Moose::after' => sub {
                my $code = pop @_;
                $meta->add_after_method_modifier($_, $code) for @_;
            };
        },
        around => sub {
            my $meta = _find_meta();
            return subname 'Moose::around' => sub {
                my $code = pop @_;
                $meta->add_around_method_modifier($_, $code) for @_;
            };
        },
        super => sub {
            my $meta = _find_meta();
            return subname 'Moose::super' => sub {};
        },
        override => sub {
            my $meta = _find_meta();
            return subname 'Moose::override' => sub {
                my ($name, $method) = @_;
                $meta->add_override_method_modifier($name => $method);
            };
        },
        inner => sub {
            my $meta = _find_meta();
            return subname 'Moose::inner' => sub {};
        },
        augment => sub {
            my $meta = _find_meta();
            return subname 'Moose::augment' => sub {
                my ($name, $method) = @_;
                $meta->add_augment_method_modifier($name => $method);
            };
        },
        confess => sub {
            return \&Carp::confess;
        },
        blessed => sub {
            return \&Scalar::Util::blessed;
        }
    );

    my $exporter = Sub::Exporter::build_exporter({ 
        exports => \%exports,
        groups  => {
            default => [':all']
        }
    });
    
    sub import {
        $CALLER = caller();

        # we should never export to main
        return if $CALLER eq 'main';

        goto $exporter;
    };
}

## Utility functions

sub _load_all_classes {
    foreach my $super (@_) {
        # see if this is already 
        # loaded in the symbol table
        next if _is_class_already_loaded($super);
        # otherwise require it ...
        ($super->require)
            || confess "Could not load superclass '$super' because : " . $UNIVERSAL::require::ERROR;
    }    
}

sub _is_class_already_loaded {
	my $name = shift;
	no strict 'refs';
	return 1 if defined ${"${name}::VERSION"} || defined @{"${name}::ISA"};
	foreach (keys %{"${name}::"}) {
		next if substr($_, -2, 2) eq '::';
		return 1 if defined &{"${name}::$_"};
	}
    return 0;
}

1;

__END__

=pod

=head1 NAME

Moose - Moose, it's the new Camel

=head1 SYNOPSIS

  package Point;
  use Moose;
  	
  has 'x' => (isa => 'Int', is => 'rw');
  has 'y' => (isa => 'Int', is => 'rw');
  
  sub clear {
      my $self = shift;
      $self->x(0);
      $self->y(0);    
  }
  
  package Point3D;
  use Moose;
  
  extends 'Point';
  
  has 'z' => (isa => 'Int');
  
  after 'clear' => sub {
      my $self = shift;
      $self->{z} = 0;
  };
  
=head1 CAVEAT

This is an early release of this module, it still needs 
some fine tuning and B<lots> more documentation. I am adopting 
the I<release early and release often> approach with this module, 
so keep an eye on your favorite CPAN mirror!

=head1 DESCRIPTION

Moose is an extension of the Perl 5 object system. 

=head2 Another object system!?!?

Yes, I know there has been an explosion recently of new ways to 
build object's in Perl 5, most of them based on inside-out objects, 
and other such things. Moose is different because it is not a new 
object system for Perl 5, but instead an extension of the existing 
object system.

Moose is built on top of L<Class::MOP>, which is a metaclass system 
for Perl 5. This means that Moose not only makes building normal 
Perl 5 objects better, but it also provides the power of metaclass 
programming.

=head2 What does Moose stand for??

Moose doesn't stand for one thing in particular, however, if you 
want, here are a few of my favorites, feel free to contribute 
more :)

=over 4

=item Make Other Object Systems Envious

=item Makes Object Orientation So Easy

=item Makes Object Orientation Spiffy- Er  (sorry ingy)

=item Most Other Object Systems Emasculate

=item My Overcraft Overfilled (with) Some Eels

=item Moose Often Ovulate Sorta Early

=item Many Overloaded Object Systems Exists 

=item Moose Offers Often Super Extensions

=item Meta Object Orientation Syntax Extensions

=back

=head1 BUILDING CLASSES WITH MOOSE

Moose makes every attempt to provide as much convience during class 
construction/definition, but still stay out of your way if you want 
it to. Here are some of the features Moose provides:

Unless specified with C<extends>, any class which uses Moose will 
inherit from L<Moose::Object>.

Moose will also manage all attributes (including inherited ones) that 
are defined with C<has>. And assuming that you call C<new> which is 
inherited from L<Moose::Object>, then this includes properly initializing 
all instance slots, setting defaults where approprtiate and performing any 
type constraint checking or coercion. 

For more details, see the ever expanding L<Moose::Cookbook>.

=head1 EXPORTED FUNCTIONS

Moose will export a number of functions into the class's namespace, which 
can then be used to set up the class. These functions all work directly 
on the current class.

=over 4

=item B<meta>

This is a method which provides access to the current class's metaclass.

=item B<extends (@superclasses)>

This function will set the superclass(es) for the current class.

This approach is recommended instead of C<use base>, because C<use base> 
actually C<push>es onto the class's C<@ISA>, whereas C<extends> will 
replace it. This is important to ensure that classes which do not have 
superclasses properly inherit from L<Moose::Object>.

=item B<with ($role)>

This will apply a given C<$role> to the local class. Role support is 
currently very experimental, see L<Moose::Role> for more details.

=item B<has ($name, %options)>

This will install an attribute of a given C<$name> into the current class. 
The list of C<%options> are the same as those provided by both 
L<Class::MOP::Attribute> and L<Moose::Meta::Attribute>, in addition to a 
few convience ones provided by Moose which are listed below:

=over 4

=item I<is =E<gt> 'rw'|'ro'>

The I<is> option accepts either I<rw> (for read/write) or I<ro> (for read 
only). These will create either a read/write accessor or a read-only 
accessor respectively, using the same name as the C<$name> of the attribute.

If you need more control over how your accessors are named, you can use the 
I<reader>, I<writer> and I<accessor> options inherited from L<Moose::Meta::Attribute>.

=item I<isa =E<gt> $type_name>

The I<isa> option uses Moose's type constraint facilities to set up runtime 
type checking for this attribute. Moose will perform the checks during class 
construction, and within any accessors. The C<$type_name> argument must be a 
string. The string can be either a class name, or a type defined using 
Moose's type defintion features.

=item I<coerce =E<gt> (1|0)>

This will attempt to use coercion with the supplied type constraint to change 
the value passed into any accessors of constructors. You B<must> have supplied 
a type constraint in order for this to work. See L<Moose::Cookbook::Recipe5>
for an example usage.

=item I<does =E<gt> $role_name>

This will accept the name of a role which the value stored in this attribute 
is expected to have consumed.

=item I<required =E<gt> (1|0)>

This marks the attribute as being required. This means a value must be supplied 
during class construction, and the attribute can never be set to C<undef> with 
an accessor. 

=item I<weak_ref =E<gt> (1|0)>

This will tell the class to strore the value of this attribute as a weakened 
reference. If an attribute is a weakened reference, it can B<not> also be coerced. 

=item I<lazy =E<gt> (1|0)>

This will tell the class to not create this slot until absolutely nessecary. 
If an attribute is marked as lazy it B<must> have a default supplied.

=item I<trigger =E<gt> $code>

The trigger option is a CODE reference which will be called after the value of 
the attribute is set. The CODE ref will be passed the instance itself, the 
updated value and the attribute meta-object (this is for more advanced fiddling
and can typically be ignored in most cases).

=back

=item B<before $name|@names =E<gt> sub { ... }>

=item B<after $name|@names =E<gt> sub { ... }>

=item B<around $name|@names =E<gt> sub { ... }>

This three items are syntactic sugar for the before, after and around method 
modifier features that L<Class::MOP> provides. More information on these can 
be found in the L<Class::MOP> documentation for now. 

=item B<super>

The keyword C<super> is a noop when called outside of an C<override> method. In 
the context of an C<override> method, it will call the next most appropriate 
superclass method with the same arguments as the original method.

=item B<override ($name, &sub)>

An C<override> method, is a way of explictly saying "I am overriding this 
method from my superclass". You can call C<super> within this method, and 
it will work as expected. The same thing I<can> be accomplished with a normal 
method call and the C<SUPER::> pseudo-package, it is really your choice. 

=item B<inner>

The keyword C<inner>, much like C<super>, is a no-op outside of the context of 
an C<augment> method. You can think of C<inner> as being the inverse of 
C<super>, the details of how C<inner> and C<augment> work is best described in 
the L<Moose::Cookbook>.

=item B<augment ($name, &sub)>

An C<augment> method, is a way of explictly saying "I am augmenting this 
method from my superclass". Once again, the details of how C<inner> and 
C<augment> work is best described in the L<Moose::Cookbook>.

=item B<confess>

This is the C<Carp::confess> function, and exported here beause I use it 
all the time. This feature may change in the future, so you have been warned. 

=item B<blessed>

This is the C<Scalar::Uti::blessed> function, it is exported here beause I 
use it all the time. It is highly recommended that this is used instead of 
C<ref> anywhere you need to test for an object's class name.

=back

=head1 CAVEATS

=over 4

=item *

It should be noted that C<super> and C<inner> can B<not> be used in the same 
method. However, they can be combined together with the same class hierarchy, 
see F<t/014_override_augment_inner_super.t> for an example. 

The reason that this is so is because C<super> is only valid within a method 
with the C<override> modifier, and C<inner> will never be valid within an 
C<override> method. In fact, C<augment> will skip over any C<override> methods 
when searching for it's appropriate C<inner>. 

This might seem like a restriction, but I am of the opinion that keeping these 
two features seperate (but interoperable) actually makes them easy to use since 
their behavior is then easier to predict. Time will tell if I am right or not.

=back

=head1 ACKNOWLEDGEMENTS

=over 4

=item I blame Sam Vilain for introducing me to the insanity that is meta-models.

=item I blame Audrey Tang for then encouraging my meta-model habit in #perl6.

=item Without Yuval "nothingmuch" Kogman this module would not be possible, 
and it certainly wouldn't have this name ;P

=item The basis of the TypeContraints module was Rob Kinyon's idea 
originally, I just ran with it.

=item Thanks to mst & chansen and the whole #moose poose for all the 
ideas/feature-requests/encouragement

=back

=head1 SEE ALSO

=over 4

=item L<Class::MOP> documentation

=item The #moose channel on irc.perl.org

=item L<http://forum2.org/moose/>

=item L<http://www.cs.utah.edu/plt/publications/oopsla04-gff.pdf>

This paper (suggested by lbr on #moose) was what lead to the implementation 
of the C<super>/C<overrride> and C<inner>/C<augment> features. If you really 
want to understand this feature, I suggest you read this.

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no 
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut