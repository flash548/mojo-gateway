package Service::ConfigValidationService;
use Mojo::Base -base, -signatures;
use JSON::Validator::Joi qw(joi);

has 'config';

sub validate_config ($self) {
  my $config = joi->object->props(
    login_page_title        => joi->string,
    landing_page            => joi->string,
    max_login_attempts      => joi->number->positive,
    mfa_secret              => joi->string,
    mfa_force_on_all        => joi->boolean,
    mfa_issuer              => joi->string,
    mfa_key_id              => joi->string,
    enable_logging          => joi->boolean,
    logging_ignore_paths    => joi->array,
    secret                  => joi->string->min(1)->required,
    admin_user              => joi->email->required,
    admin_pass              => joi->string(1)->required,
    db_type                 => joi->string->enum(["pg", "sqlite"]),
    db_uri                  => joi->string,
    cookie_name             => joi->string,
    strip_headers_to_client => joi->array,
    jwt_secret              => joi->string->min(1)->required,
    routes                  => joi->object->required,
    password_valid_days     => joi->number->positive->required,
    password_complexity     => joi->object->required,
    default_route           => joi->object->required,
    test                    => joi->boolean,
    config_override         => joi->boolean    # this is put in by Mojo on config overrides in testing
  );

  if ($self->config->{ mfa_secret } || $self->config->{ mfa_issuer } || $self->config->{ mfa_key_id }) {
    die "MFA secret/issuer/key_id must ALL be set if any of the others are set"
      unless $self->config->{ mfa_secret } && $self->config->{ mfa_issuer } && $self->config->{ mfa_key_id };
  }

  say "Validating config...";
  my @errors = $config->strict->validate($self->config);
  if (@errors) {
    die @errors;
  }

  my $password_complex_config = joi->object->props(
    min_length => joi->number->min(1)->required,
    alphas     => joi->number->min(0)->required,
    numbers    => joi->number->min(0)->required,
    specials   => joi->number->min(0)->required,
    spaces     => joi->boolean->required
  );

  say "Validating password complexity config...";
  @errors = $password_complex_config->strict->validate($self->config->{ password_complexity });
  if (@errors) {
    die @errors;
  }

  # validation spec for an actual proxy to another service spec
  my $route_config_spec = joi->object->props(
    uri              => joi->string->required,
    enable_jwt       => joi->boolean,
    requires_login   => joi->boolean,
    jwt_claims       => joi->object,
    transforms       => joi->array,
    other_headers    => joi->object,
    additional_paths => joi->array,
  );

  # validation spec for a local / template spec
  my $route_local_spec = joi->object->props(template_name => joi->string->required, requires_login => joi->boolean);

  say "Validating default route config...";
  if (defined($self->config->{ default_route }->{ template_name })
    && !defined($self->config->{ default_route }->{ uri })) {
    @errors = $route_local_spec->validate($self->config->{ default_route });
  } elsif (!defined($self->config->{ default_route }->{ template_name })
    && defined($self->config->{ default_route }->{ uri })) {
    @errors = $route_config_spec->validate($self->config->{ default_route });
  } else {
    @errors = ('Cannot specify both uri and template fields on the default route spec');
  }
  if (@errors) {
    die @errors;
  }

  say "Validating route config...";
  for my $route (keys($self->config->{ routes }->%*)) {
    say "On route " . $route;
    if (defined($self->config->{ routes }->{ $route }->{ template_name })
      && !defined($self->config->{ routes }->{ $route }->{ uri })) {
      @errors = $route_local_spec->validate($self->config->{ routes }->{ $route });
    } elsif (!defined($self->config->{ routes }->{ $route }->{ template_name })
      && defined($self->config->{ routes }->{ $route }->{ uri })) {
      @errors = $route_config_spec->validate($self->config->{ routes }->{ $route });
    } else {
      @errors = ('Cannot specify both uri and template fields on a proxy route spec');
    }
    if (@errors) {
      die @errors;
    }
  }

  say "App Config - Valid ✅";
}


1;
