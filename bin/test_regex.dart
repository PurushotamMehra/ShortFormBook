void main() {
  final text =
      """Each day in camp began at 6:30 A.M., when the night watchman drew off a tablespoon of gasoline from a drum in the galley and poured it into a small
  
  Another text. With multiple. Sentences! Yes?""";

  // Split on punctuation followed by space, or just space if it's too hard to get perfect sentences
  // Actually, we can just split by spaces and group by words.
  // Wait, if the goal is to split EXACTLY at word boundaries without losing text, doing a split by ' ' or RegExp(r'\s+') is safest, though it breaks mid-sentence.
  // The user states: "but we cannot afford the loss of texts."
  // If we just want to break into SubChunks avoiding sentence breaks *if possible*, but preserving 100% of text:

  // Strategy:
  // Match sentences, but if the end of the matches doesn't reach text.length, add the remainder!
  final RegExp sentenceRe = RegExp(r'[^.!?]+[.!?]*(?:\s+|$)|[^.!?]+$');
  final matches = sentenceRe.allMatches(text);

  int lastEnd = 0;
  for (final match in matches) {
    print('--- MATCH ---');
    print(match.group(0));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    print('--- REMAINDER ---');
    print(text.substring(lastEnd));
  }

  print('--- STRING SPLIT INCLUSIVE ---');
  // Match everything: either a sentence ending in punctuation+space, OR a chunk of characters.
  final RegExp safeRe = RegExp(r'.*?[.!?](?:\s+|$)|.+');
  final safeMatches = safeRe.allMatches(text);
  for (final match in safeMatches) {
    print('SAFE: "${match.group(0)}"');
  }
}
