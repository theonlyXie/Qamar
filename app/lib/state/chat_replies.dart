class ChatReply {
  final String d; // decision
  final String r; // reason
  final String a; // action label, '' means no action button
  const ChatReply({required this.d, required this.r, required this.a});
}

/// Canned Ask-Qamar responses, ported from the prototype's replies().
/// A real build swaps this for the server-gateway AI response.
const List<ChatReply> kChatRepliesAr = [
  ChatReply(d: 'كمّل يومك عادي.', r: 'باقيلك حوالي ٣٥ جم بروتين و٦٢٠ سعر. عشا خفيف فيه بروتين هيقفل اليوم صح.', a: 'وريني العشا'),
  ChatReply(d: 'هعدّل العشا بخطوة واحدة.', r: 'هستبدل الأرز بسلطة وأزوّد البروتين، والباقي زي ما هو.', a: 'اعمل كده'),
  ChatReply(d: 'اليوم مش ضاع.', r: 'مش بنبدأ من جديد — هنعدل المسار بخطوة واحدة بس.', a: 'عدّل المسار'),
  ChatReply(d: 'التقدير تقريبي مش دقيق.', r: 'الكمية اتقدرت من وصفك، وتقدر تعدلها من تفاصيل الوجبة في أي وقت.', a: ''),
];

const List<ChatReply> kChatRepliesEn = [
  ChatReply(d: 'Carry on with your day.', r: 'You have about 35 g protein and 620 kcal left. A light protein dinner closes the day well.', a: 'Show me dinner'),
  ChatReply(d: 'I’ll adjust dinner in one step.', r: 'I’ll swap the rice for salad and raise the protein; everything else stays.', a: 'Do it'),
  ChatReply(d: 'The day is not lost.', r: 'We are not starting over — one step puts you back on the route.', a: 'Adjust the route'),
  ChatReply(d: 'That estimate is approximate.', r: 'The portion came from your description; you can edit it from the meal detail any time.', a: ''),
];

const List<String> kChatPromptsAr = ['أكلت كشري النهاردة، أعمل إيه؟', 'أنا تعبان ومش ناوي أطبخ', 'فطرت متأخر أوي'];
const List<String> kChatPromptsEn = ['I ate koshary today, what now?', 'I’m tired and not cooking', 'I had a very late breakfast'];

const List<String> kChatSuggestionsAr = ['أكلت كشري، أعمل إيه؟', 'عدّل العشا', 'أنا تعبان النهاردة'];
const List<String> kChatSuggestionsEn = ['I ate koshary, what now?', 'Adjust dinner', 'I’m tired today'];
