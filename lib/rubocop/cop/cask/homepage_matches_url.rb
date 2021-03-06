require 'forwardable'
require 'public_suffix'

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's homepage matches the download url,
      # or if it doesn't, checks if a comment in the form
      # `# example.com was verified as official when first introduced to the cask`
      # is present.
      class HomepageMatchesUrl < Cop # rubocop:disable Metrics/ClassLength
        extend Forwardable
        include CaskHelp

        REFERENCE_URL = 'https://github.com/Homebrew/homebrew-cask/blob/master/doc/cask_language_reference/stanzas/url.md#when-url-and-homepage-hostnames-differ-add-a-comment'.freeze

        COMMENT_FORMAT = /# [^ ]+ was verified as official when first introduced to the cask/

        MSG_NO_MATCH = '`%<url>s` does not match `%<full_url>s`'.freeze

        MSG_MISSING = '`%<domain>s` does not match `%<homepage>s`, a comment has to be added ' \
                      'above the `url` stanza. For details, see ' + REFERENCE_URL

        MSG_WRONG_FORMAT = '`%<comment>s` does not match the expected comment format. ' \
                           'For details, see ' + REFERENCE_URL

        MSG_UNNECESSARY = '`%<domain>s` matches `%<homepage>s`, the comment above the `url` ' \
                          'stanza is unnecessary'.freeze

        def on_cask(cask_block)
          @cask_block = cask_block
          return unless homepage_stanza

          add_offenses
        end

        private

        attr_reader :cask_block
        def_delegators :cask_block, :cask_node, :toplevel_stanzas,
                       :sorted_toplevel_stanzas

        def add_offenses
          toplevel_stanzas.select(&:url?).each do |url|
            next if add_offense_unnecessary_comment(url)
            next if add_offense_missing_comment(url)
            next if add_offense_no_match(url)
            next if add_offense_wrong_format(url)
          end
        end

        def add_offense_unnecessary_comment(stanza)
          return unless comment?(stanza)
          return unless url_match_homepage?(stanza)
          return unless comment_matches_url?(stanza)

          comment = comment(stanza).loc.expression
          add_offense(comment,
                      location: comment,
                      message: format(MSG_UNNECESSARY, domain: domain(stanza), homepage: homepage))
        end

        def add_offense_missing_comment(stanza)
          return if url_match_homepage?(stanza)
          return if !url_match_homepage?(stanza) && comment?(stanza)

          range = stanza.source_range
          url_domain = domain(stanza)
          add_offense(range, location: range, message: format(MSG_MISSING, domain: url_domain, homepage: homepage))
        end

        def add_offense_no_match(stanza)
          return if url_match_homepage?(stanza)
          return unless comment?(stanza)
          return if !url_match_homepage?(stanza) && comment_matches_url?(stanza)

          comment = comment(stanza).loc.expression
          add_offense(comment,
                      location: comment,
                      message: format(MSG_NO_MATCH, url: url_from_comment(stanza), full_url: full_url(stanza)))
        end

        def add_offense_wrong_format(stanza)
          return if url_match_homepage?(stanza)
          return unless comment?(stanza)
          return if comment_matches_format?(stanza)

          comment = comment(stanza).loc.expression
          add_offense(comment,
                      location: comment,
                      message: format(MSG_WRONG_FORMAT, comment: comment(stanza).text))
        end

        def comment?(stanza)
          !stanza.comments.empty?
        end

        def comment(stanza)
          stanza.comments.last
        end

        def comment_matches_format?(stanza)
          comment(stanza).text =~ COMMENT_FORMAT
        end

        def url_from_comment(stanza)
          comment(stanza).text
            .sub(/[^ ]*# ([^ ]+) .*/, '\1')
        end

        def comment_matches_url?(stanza)
          full_url(stanza).include?(url_from_comment(stanza))
        end

        def strip_url_scheme(url)
          url.sub(%r{^.*://(www\.)?}, '')
        end

        def domain(stanza)
          strip_url_scheme(extract_url(stanza)).gsub(%r{^([^/]+).*}, '\1')
        end

        def extract_url(stanza)
          string = stanza.stanza_node.children[2]
          return string.str_content if string.str_type?

          string.to_s.gsub(%r{.*"([a-z0-9]+\:\/\/[^"]+)".*}m, '\1')
        end

        def url_match_homepage?(stanza)
          PublicSuffix.domain(domain(stanza)) == homepage
        end

        def full_url(stanza)
          strip_url_scheme(extract_url(stanza))
        end

        def homepage
          PublicSuffix.domain(domain(homepage_stanza))
        end

        def homepage_stanza
          toplevel_stanzas.find(&:homepage?)
        end
      end
    end
  end
end
