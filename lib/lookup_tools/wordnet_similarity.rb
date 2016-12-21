require 'java'
require_relative 'jar/ws4j-1.0.1.jar'

java_import 'edu.cmu.lti.lexical_db.ILexicalDatabase'
java_import 'edu.cmu.lti.lexical_db.NictWordNet'
java_import 'edu.cmu.lti.ws4j.RelatednessCalculator'
java_import 'edu.cmu.lti.ws4j.impl.Lin'
java_import 'edu.cmu.lti.ws4j.impl.Path'
java_import 'edu.cmu.lti.ws4j.impl.WuPalmer'
java_import 'edu.cmu.lti.ws4j.util.WS4JConfiguration'

##
# Looks up the similarity of two words or tags using WordNet, through WordnetSimilarirty4Java
#
# WS4J is released under the GNU GPL v2 licence and so is redistributed here (in jar/ws4j-1.0.1.jar)
# in unmodified form, originally obtained from the creator's website: Source: https://code.google.com/p/ws4j/
#
# The code in this class is a wrapper for WS4J to enable specific applications within this source code.
##

module LookupTools
  class WordnetSimilarity

    def initialize
      @db = NictWordNet.new
      WS4JConfiguration.getInstance().setMFS(true)
      @rc = Lin.new(@db)
      @cache = Hash.new { |h, k| h[k] = {} }
    end

    def tag_similarity(p1, p2)
      p1, p2 = [p1, p2].sort
      if @cache[p1][p2]
        return @cache[p1][p2]
      end
      k1, v1 = p1.split(':')
      k2, v2 = p2.split(':')
      similarity = (word_similarity(k1, k2) + word_similarity(v1, v2)) / 2.0
      @cache[p1][p2] = similarity
    end

    def word_similarity(w1, w2)
      return 1.0 if w1 == w2
      pos_pairs = @rc.getPOSPairs()
      max_score = 0.0

      pos_pairs.each do |posPair|
        synsets1 = @db.getAllConcepts(w1, posPair[0].to_s)
        synsets2 = @db.getAllConcepts(w2, posPair[1].to_s)

        synsets1.each do |synset1|
          synsets2.each do |synset2|
            relatedness = @rc.calcRelatednessOfSynset(synset1, synset2)
            score = relatedness.getScore()
            max_score = score if max_score.nil? or (score > max_score)
          end
        end

      end

      max_score
    end

  end
end