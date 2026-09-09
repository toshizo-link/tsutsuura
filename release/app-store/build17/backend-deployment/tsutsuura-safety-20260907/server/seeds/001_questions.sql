-- 370 unique Japanese family conversation prompts; repeat-safe on existing databases.
-- Publish windows use minutes after midnight in APP_TIMEZONE.
-- Questions about this day arrive at 17:00–19:00; other questions at 09:00–19:00.
-- Narrow an entry's window (even to one minute) to specify a publishing time.

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、いちばん心に残ったことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、いちばん心に残ったことは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近「ありがとう」と思ったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近「ありがとう」と思ったことは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族といっしょにやってみたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族といっしょにやってみたいことは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日の自分を色にたとえると何色？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日の自分を色にたとえると何色？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ好きだった遊びは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ好きだった遊びは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今、楽しみにしていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今、楽しみにしていることは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族のすてきだと思うところは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族のすてきだと思うところは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、だれかに伝えたいひとことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、だれかに伝えたいひとことは？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近笑ったのはどんなとき？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近笑ったのはどんなとき？' AND available_on IS NULL);

-- はじめの質問
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '明日ひとつだけできるなら、何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '明日ひとつだけできるなら、何をしたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、よく遊んだ場所はどんなところ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、よく遊んだ場所はどんなところ？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '何度食べても飽きない料理は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '何度食べても飽きない料理は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に聞いてみたいことをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に聞いてみたいことをひとつ教えて。' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、おいしいと思ったものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、おいしいと思ったものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな季節と、その理由を教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな季節と、その理由を教えて。' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'もう一度訪れたい場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'もう一度訪れたい場所は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '時間を忘れて楽しめることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '時間を忘れて楽しめることは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近、自分なりに頑張ったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近、自分なりに頑張ったことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '明日の楽しみをひとつ作るなら、何にする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '明日の楽しみをひとつ作るなら、何にする？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ好きだったおやつは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ好きだったおやつは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に作ってあげたい料理は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に作ってあげたい料理は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の声で聞くと、ほっとする言葉は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の声で聞くと、ほっとする言葉は？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、窓の外には何が見えた？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、窓の外には何が見えた？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '雨の音を聞くと、どんな気持ちになる？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '雨の音を聞くと、どんな気持ちになる？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '近所の好きな道を教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '近所の好きな道を教えて。' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '部屋に流したい音楽は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '部屋に流したい音楽は？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '言われるとうれしい言葉は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '言われるとうれしい言葉は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一日だけ何かの名人になれるなら、何を選ぶ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一日だけ何かの名人になれるなら、何を選ぶ？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '初めて自分で買ったものを覚えている？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '初めて自分で買ったものを覚えている？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かに教わって覚えている料理のこつは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かに教わって覚えている料理のこつは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と一緒に見たい景色は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と一緒に見たい景色は？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、思わず笑顔になったことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、思わず笑顔になったことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな花は何？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな花は何？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅の荷物に必ず入れるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅の荷物に必ず入れるものは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '大切に使っている道具をひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '大切に使っている道具をひとつ教えて。' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '困ったときに思い出す言葉はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '困ったときに思い出す言葉はある？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族で小さな庭を作るなら、何を植えたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族で小さな庭を作るなら、何を植えたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '学校へ通う道で、楽しみだったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '学校へ通う道で、楽しみだったことは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'おにぎりの具をひとつ選ぶなら、何が好き？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'おにぎりの具をひとつ選ぶなら、何が好き？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族との写真を撮るなら、どこで撮りたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族との写真を撮るなら、どこで撮りたい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、誰かと交わした言葉で覚えているものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、誰かと交わした言葉で覚えているものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '散歩の途中で見つけるとうれしいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '散歩の途中で見つけるとうれしいものは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '電車の窓から見たい景色は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '電車の窓から見たい景色は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '気持ちが落ち着く家の場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '気持ちが落ち着く家の場所は？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かに助けてもらって、心に残っていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かに助けてもらって、心に残っていることは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の喫茶店に名前をつけるなら？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の喫茶店に名前をつけるなら？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、得意だったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、得意だったことは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '寒い日に食べたくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '寒い日に食べたくなるものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に教えてもらってうれしかったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に教えてもらってうれしかったことは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、自分をほめてあげたいことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、自分をほめてあげたいことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '朝と夕方、どちらの空が好き？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '朝と夕方、どちらの空が好き？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '初めて訪れた町で、まず何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '初めて訪れた町で、まず何をしたい？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近読んだり見たりして、面白かったものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近読んだり見たりして、面白かったものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '小さな幸せを感じるのは、どんなとき？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '小さな幸せを感じるのは、どんなとき？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '空を飛べるなら、最初にどこを見に行きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '空を飛べるなら、最初にどこを見に行きたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔のおうちで、いちばん好きだった場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔のおうちで、いちばん好きだった場所は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '暑い日に飲みたくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '暑い日に飲みたくなるものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に教えてあげられることはある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に教えてあげられることはある？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、気づいた小さな変化は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、気づいた小さな変化は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '季節の変わり目を、何で感じる？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '季節の変わり目を、何で感じる？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅先から家族に送るなら、どんな写真？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅先から家族に送るなら、どんな写真？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '何かを作るなら、どんなものを作りたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '何かを作るなら、どんなものを作りたい？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '以前より上手になったと思うことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '以前より上手になったと思うことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一週間の休みができたら、どう過ごしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一週間の休みができたら、どう過ごしたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ夢中で集めたものはある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ夢中で集めたものはある？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '思い出の味といえば、何を思い浮かべる？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '思い出の味といえば、何を思い浮かべる？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と過ごす、理想の休日はどんな一日？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と過ごす、理想の休日はどんな一日？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、ほっとしたのはどんなとき？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、ほっとしたのはどんなとき？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな鳥や、その鳴き声はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな鳥や、その鳴き声はある？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の町のおいしいものをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の町のおいしいものをひとつ教えて。' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな映画やお話の場面をひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな映画やお話の場面をひとつ教えて。' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '大切にしている約束はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '大切にしている約束はある？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '未来の自分にひとこと残すなら？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '未来の自分にひとこと残すなら？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '思い出に残っている先生はどんな人？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '思い出に残っている先生はどんな人？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '朝ごはんにあるとうれしいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '朝ごはんにあるとうれしいものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族といっしょに食べたいおやつは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族といっしょに食べたいおやつは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、耳に残った音は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、耳に残った音は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '海と山、今行くならどちらを選ぶ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '海と山、今行くならどちらを選ぶ？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '懐かしい駅やバス停はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '懐かしい駅やバス停はある？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お気に入りの服は、どんなところが好き？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お気に入りの服は、どんなところが好き？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の好きなところをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の好きなところをひとつ教えて。' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きなものだけを並べる棚に、何を置きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きなものだけを並べる棚に、何を置きたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '給食やお弁当で、好きだったおかずは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '給食やお弁当で、好きだったおかずは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな果物と、その好きなところを教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな果物と、その好きなところを教えて。' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の誰かと似ていると思うところは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の誰かと似ていると思うところは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、目に入ってきれいだと思った色は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、目に入ってきれいだと思った色は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな木や葉っぱの形はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな木や葉っぱの形はある？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅の思い出に残っている人との出会いは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅の思い出に残っている人との出会いは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '長く続けている小さな習慣は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '長く続けている小さな習慣は？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '年を重ねて、楽しめるようになったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '年を重ねて、楽しめるようになったことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族で一冊の本を作るなら、どんな内容にしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族で一冊の本を作るなら、どんな内容にしたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ楽しみにしていた行事は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ楽しみにしていた行事は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'みそ汁に入っているとうれしい具は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'みそ汁に入っているとうれしい具は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の意外な一面で、覚えていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の意外な一面で、覚えていることは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、体を休めるためにしたことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、体を休めるためにしたことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '風が気持ちいい日にしたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '風が気持ちいい日にしたいことは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家の近くで、ほっとする場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家の近くで、ほっとする場所は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家で過ごす雨の日に、楽しみたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家で過ごす雨の日に、楽しみたいことは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '気持ちを切り替えたいとき、何をする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '気持ちを切り替えたいとき、何をする？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '動物と話せるなら、何を聞いてみたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '動物と話せるなら、何を聞いてみたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔、家で呼ばれていたあだ名はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔、家で呼ばれていたあだ名はある？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族みんなで囲みたい料理は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族みんなで囲みたい料理は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に自分の好きな曲を一曲紹介するなら？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に自分の好きな曲を一曲紹介するなら？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、やってよかったと思うことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、やってよかったと思うことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '春の楽しみをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '春の楽しみをひとつ教えて。' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '歩いていて見つけた、すてきなお店は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '歩いていて見つけた、すてきなお店は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな香りをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな香りをひとつ教えて。' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '人から教わったことで、役に立っていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '人から教わったことで、役に立っていることは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '新しいおにぎりを考えるなら、何を入れたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '新しいおにぎりを考えるなら、何を入れたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、よく口ずさんだ歌は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、よく口ずさんだ歌は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お茶の時間に合わせたいお菓子は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お茶の時間に合わせたいお菓子は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族との食事で、いつの間にか決まった役割はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族との食事で、いつの間にか決まった役割はある？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、新しく知ったことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、新しく知ったことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '夏の好きなところは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '夏の好きなところは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '温泉に行くなら、どんな景色を眺めたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '温泉に行くなら、どんな景色を眺めたい？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '飾って眺めたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '飾って眺めたいものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近、勇気を出してやってみたことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近、勇気を出してやってみたことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分だけの記念切手を作るなら、何の絵にする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分だけの記念切手を作るなら、何の絵にする？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '夏休みの思い出をひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '夏休みの思い出をひとつ教えて。' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分なりの、おいしい食べ方があるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分なりの、おいしい食べ方があるものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の持ち物で、持ち主らしいなと思うものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の持ち物で、持ち主らしいなと思うものは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、うれしかった知らせはある？なければ、待っている知らせは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、うれしかった知らせはある？なければ、待っている知らせは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '秋の風景といえば、何を思い浮かべる？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '秋の風景といえば、何を思い浮かべる？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一日だけ住んでみたい町は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一日だけ住んでみたい町は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '使うたびにうれしくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '使うたびにうれしくなるものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '心に残っている、親切なひとことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '心に残っている、親切なひとことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一日だけ昔へ戻るなら、何を見てみたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一日だけ昔へ戻るなら、何を見てみたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '冬の朝、子どものころはどう過ごしていた？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '冬の朝、子どものころはどう過ごしていた？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お店でつい選んでしまう料理は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お店でつい選んでしまう料理は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族からもらってうれしかったものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族からもらってうれしかったものは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、手ざわりがよかったものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、手ざわりがよかったものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '冬の楽しみをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '冬の楽しみをひとつ教えて。' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '地図を見て気になる場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '地図を見て気になる場所は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '新しく始めてみたい趣味は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '新しく始めてみたい趣味は？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分が大事にしたい時間は、どんな時間？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分が大事にしたい時間は、どんな時間？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族のために小さな賞を作るなら、どんな賞？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族のために小さな賞を作るなら、どんな賞？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ読んで好きだったお話は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ読んで好きだったお話は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '初めて食べて、おいしいと思ったものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '初めて食べて、おいしいと思ったものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と大笑いした出来事は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と大笑いした出来事は？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、手に取ったお気に入りのものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、手に取ったお気に入りのものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '花を一輪飾るなら、どこに置きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '花を一輪飾るなら、どこに置きたい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅先で買ってよかったお土産は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅先で買ってよかったお土産は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '音楽を聴くとき、どんな場所が好き？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '音楽を聴くとき、どんな場所が好き？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '小さな達成感を感じるのは、どんなとき？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '小さな達成感を感じるのは、どんなとき？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'おうちで小さなお祭りをするなら、何を用意したい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'おうちで小さなお祭りをするなら、何を用意したい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '初めてできるようになって、うれしかったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '初めてできるようになって、うれしかったことは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お祝いの日に食べたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お祝いの日に食べたいものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族で新しく作ってみたい習慣は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族で新しく作ってみたい習慣は？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、誰かにすすめたいと思ったものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、誰かにすすめたいと思ったものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '虹を見たときの思い出はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '虹を見たときの思い出はある？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '乗ってみたい乗りものはある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '乗ってみたい乗りものはある？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '得意な家事や、好きな家事はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '得意な家事や、好きな家事はある？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '待つ時間を楽しくする工夫はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '待つ時間を楽しくする工夫はある？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな色を集めた花束を作るなら、どんな花束？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな色を集めた花束を作るなら、どんな花束？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔の友だちとの、忘れられない出来事は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔の友だちとの、忘れられない出来事は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家の定番料理をひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家の定番料理をひとつ教えて。' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族とゆっくり話すなら、何の話をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族とゆっくり話すなら、何の話をしたい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、外の空気はどんな感じだった？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、外の空気はどんな感じだった？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '星空を眺めるなら、誰とどこへ行きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '星空を眺めるなら、誰とどこへ行きたい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の町の好きなところを、家族に紹介して。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の町の好きなところを、家族に紹介して。' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '片づけで自分なりに工夫していることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '片づけで自分なりに工夫していることは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '思い出すと元気になる出来事は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '思い出すと元気になる出来事は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一つだけ新しい楽器を習うなら、何がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一つだけ新しい楽器を習うなら、何がいい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ飼っていた、または好きだった生き物は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ飼っていた、または好きだった生き物は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お弁当にひとつだけ好きなおかずを入れるなら？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お弁当にひとつだけ好きなおかずを入れるなら？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族で一枚の絵を描くなら、何を描きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族で一枚の絵を描くなら、何を描きたい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、自分のために使った時間は何をした？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、自分のために使った時間は何をした？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家の近くで、自然を感じる場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家の近くで、自然を感じる場所は？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '思い出に残る橋や坂道はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '思い出に残る橋や坂道はある？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '手紙を書くなら、どんな便せんを選びたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '手紙を書くなら、どんな便せんを選びたい？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かにしてもらって、自分もまねしたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かにしてもらって、自分もまねしたいことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '身近な道具に便利な力を一つ足すなら？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '身近な道具に便利な力を一つ足すなら？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔のお祭りで、いちばん楽しみだったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔のお祭りで、いちばん楽しみだったことは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな麺料理は何？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな麺料理は何？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の中で、自分がよく頼まれることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の中で、自分がよく頼まれることは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、誰かのやさしさを感じたことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、誰かのやさしさを感じたことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '育ててみたい植物は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '育ててみたい植物は？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅行の計画で、いちばん楽しみなことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅行の計画で、いちばん楽しみなことは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '部屋にひとつ色を足すなら、何色にしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '部屋にひとつ色を足すなら、何色にしたい？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近「なるほど」と思ったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近「なるほど」と思ったことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お弁当を自由に名づけるなら、どんな名前にする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お弁当を自由に名づけるなら、どんな名前にする？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、おこづかいを何に使った？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、おこづかいを何に使った？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'いちばん好きな食べものの香りは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'いちばん好きな食べものの香りは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族が疲れていたら、どんな言葉をかけたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族が疲れていたら、どんな言葉をかけたい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、口ずさんだり聴いたりした曲は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、口ずさんだり聴いたりした曲は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '水の音で好きなのは、川、波、雨のどれ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '水の音で好きなのは、川、波、雨のどれ？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅先で朝を迎えるなら、海辺、山の中、町のどこ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅先で朝を迎えるなら、海辺、山の中、町のどこ？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お気に入りの器は、どんな形や模様？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お気に入りの器は、どんな形や模様？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の暮らしで、大切にしていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の暮らしで、大切にしていることは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と宝探しをするなら、何を宝物にしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と宝探しをするなら、何を宝物にしたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、雨の日には何をして遊んだ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、雨の日には何をして遊んだ？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かと一緒に食べて、楽しかった思い出は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かと一緒に食べて、楽しかった思い出は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と昔の話をするなら、何から話したい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と昔の話をするなら、何から話したい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、楽しかった会話はどんな話だった？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、楽しかった会話はどんな話だった？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '季節を感じる香りといえば？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '季節を感じる香りといえば？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'もう一度食べに行きたいお店は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'もう一度食べに行きたいお店は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家で少しぜいたくをするなら、何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家で少しぜいたくをするなら、何をしたい？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '失敗から覚えて、今は役立っていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '失敗から覚えて、今は役立っていることは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'おとぎ話の世界へ行くなら、どんな場所を訪れたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'おとぎ話の世界へ行くなら、どんな場所を訪れたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '遠足で覚えている景色や出来事は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '遠足で覚えている景色や出来事は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '焼きたてで食べたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '焼きたてで食べたいものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に自分の町を案内するなら、どこへ連れていく？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に自分の町を案内するなら、どこへ連れていく？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、片づけたり整えたりした場所はある？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、片づけたり整えたりした場所はある？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '雪の日の思い出をひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '雪の日の思い出をひとつ教えて。' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と日帰りで出かけるなら、どこへ行きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と日帰りで出かけるなら、どこへ行きたい？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '毎日使うもので、家族にすすめたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '毎日使うもので、家族にすすめたいものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '忙しい日に、自分へかけたい言葉は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '忙しい日に、自分へかけたい言葉は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の町に一つ増やせるなら、何があるとうれしい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の町に一つ増やせるなら、何があるとうれしい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、家の手伝いで何をしていた？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、家の手伝いで何をしていた？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '春になると食べたくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '春になると食べたくなるものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に伝えたい、小さな自慢はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に伝えたい、小さな自慢はある？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、いい香りだと思ったものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、いい香りだと思ったものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '日なたで過ごすなら、何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '日なたで過ごすなら、何をしたい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅で少し困ったけれど、今は笑えることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅で少し困ったけれど、今は笑えることは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '見ていて元気が出る番組や動画は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '見ていて元気が出る番組や動画は？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔の自分に「大丈夫」と伝えたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔の自分に「大丈夫」と伝えたいことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かに一日を案内してもらうなら、どんな一日がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かに一日を案内してもらうなら、どんな一日がいい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔、楽しみにしていたテレビやラジオの番組は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔、楽しみにしていたテレビやラジオの番組は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '秋の味覚で楽しみなものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '秋の味覚で楽しみなものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と一緒に作ってみたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と一緒に作ってみたいものは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、予定と違って面白かったことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、予定と違って面白かったことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '木陰でひと休みするとき、何を飲みたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '木陰でひと休みするとき、何を飲みたい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'ずっと覚えている建物は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'ずっと覚えている建物は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '手を動かす作業で、好きなものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '手を動かす作業で、好きなものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '覚えていてもらえるとうれしい、自分のことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '覚えていてもらえるとうれしい、自分のことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族で歌を作るなら、どんな言葉を入れたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族で歌を作るなら、どんな言葉を入れたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころの宝物は何だった？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころの宝物は何だった？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅先で出会った、おいしいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅先で出会った、おいしいものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の口ぐせで思い浮かぶものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の口ぐせで思い浮かぶものは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日の空を、ひとことで表すなら？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日の空を、ひとことで表すなら？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '名前を知りたいと思った花や生き物はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '名前を知りたいと思った花や生き物はある？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'のんびり座って過ごしたい場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'のんびり座って過ごしたい場所は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分にとって、心地よい休日の始め方は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分にとって、心地よい休日の始め方は？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分のペースを取り戻すには、何をするといい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分のペースを取り戻すには、何をするといい？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一度だけ体験してみたい仕事はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一度だけ体験してみたい仕事はある？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '学校の休み時間は、どう過ごすのが好きだった？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '学校の休み時間は、どう過ごすのが好きだった？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分で育てて食べてみたい野菜や果物は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分で育てて食べてみたい野菜や果物は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族からの連絡で、うれしいのはどんな知らせ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族からの連絡で、うれしいのはどんな知らせ？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、懐かしいと思ったことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、懐かしいと思ったことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '夕焼けを見たくなる場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '夕焼けを見たくなる場所は？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '初めて行く人におすすめしたい、自分の町の場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '初めて行く人におすすめしたい、自分の町の場所は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな本や雑誌を読むのは、どんなとき？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな本や雑誌を読むのは、どんなとき？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近、誰かをすてきだと思ったのはどんなとき？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近、誰かをすてきだと思ったのはどんなとき？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな景色を窓の外に置けるなら、何を選ぶ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな景色を窓の外に置けるなら、何を選ぶ？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、好きだった文房具は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、好きだった文房具は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'いつか挑戦してみたい料理は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'いつか挑戦してみたい料理は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族で音楽を楽しむなら、歌う、聴く、演奏するのどれ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族で音楽を楽しむなら、歌う、聴く、演奏するのどれ？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、ゆっくり味わえたものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、ゆっくり味わえたものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '新緑と紅葉、どちらを見に行きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '新緑と紅葉、どちらを見に行きたい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅先の市場や商店街で、見たいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅先の市場や商店街で、見たいものは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '何かを集めるなら、何を集めたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '何かを集めるなら、何を集めたい？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一つだけ感謝を手紙に書くなら、何を書きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一つだけ感謝を手紙に書くなら、何を書きたい？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '新しい祝日を作るなら、何を楽しむ日にしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '新しい祝日を作るなら、何を楽しむ日にしたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '運動会で思い出に残っていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '運動会で思い出に残っていることは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'ごはんに合う、好きなおかずは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'ごはんに合う、好きなおかずは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と一緒に眺めたい花は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と一緒に眺めたい花は？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、誰かにしてあげた小さなことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、誰かにしてあげた小さなことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '庭やベランダにひとつ置くなら、何がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '庭やベランダにひとつ置くなら、何がいい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '船に乗ってみるなら、どこへ行きたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '船に乗ってみるなら、どこへ行きたい？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家で音を楽しむなら、何の音が好き？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家で音を楽しむなら、何の音が好き？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '長く続けてきて、よかったと思うことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '長く続けてきて、よかったと思うことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '小さな絵本の主人公になるなら、どんなお話がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '小さな絵本の主人公になるなら、どんなお話がいい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔のお正月は、どんなふうに過ごしていた？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔のお正月は、どんなふうに過ごしていた？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな飲みものを、どんなときに飲む？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな飲みものを、どんなときに飲む？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族との待ち合わせに選びたい場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族との待ち合わせに選びたい場所は？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、家の中でいちばん長くいた場所は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、家の中でいちばん長くいた場所は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'いつか見てみたい自然の景色は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'いつか見てみたい自然の景色は？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '道案内をするとき、目印にしたくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '道案内をするとき、目印にしたくなるものは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '得意なことを一つ披露するなら、何をする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '得意なことを一つ披露するなら、何をする？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '小さな挑戦をするなら、今は何を選ぶ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '小さな挑戦をするなら、今は何を選ぶ？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族でおそろいのものを持つなら、何がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族でおそろいのものを持つなら、何がいい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、大人になったら何をしたいと思っていた？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、大人になったら何をしたいと思っていた？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'おすそ分けするなら、何を選びたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'おすそ分けするなら、何を選びたい？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に一冊すすめるなら、どんな本や雑誌？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に一冊すすめるなら、どんな本や雑誌？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、いつもより少し工夫したことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、いつもより少し工夫したことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '季節の行事で、好きなものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '季節の行事で、好きなものは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅の写真を一枚飾るなら、どんな景色？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅の写真を一枚飾るなら、どんな景色？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな模様や柄はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな模様や柄はある？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お祝いしてあげたい、自分のできたことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お祝いしてあげたい、自分のできたことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分の好きなものを地図にするなら、何を載せたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分の好きなものを地図にするなら、何を載せたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '初めて料理をしたとき、何を作った？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '初めて料理をしたとき、何を作った？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '料理をするとき、好きな作業はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '料理をするとき、好きな作業はある？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族が来る日に、用意しておきたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族が来る日に、用意しておきたいものは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、一枚写真に残すなら何を選ぶ？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、一枚写真に残すなら何を選ぶ？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '雨の日ならではの楽しみは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '雨の日ならではの楽しみは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お弁当を持って出かけたい場所は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お弁当を持って出かけたい場所は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔から変わらず好きなものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔から変わらず好きなものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かと仲良くなるきっかけになったことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かと仲良くなるきっかけになったことは？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'これから覚えてみたい言葉や技は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'これから覚えてみたい言葉や技は？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔よく通ったお店は、どんなお店だった？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔よく通ったお店は、どんなお店だった？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '買い物で見つけるとうれしい食材は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '買い物で見つけるとうれしい食材は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に助けてもらって、覚えていることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に助けてもらって、覚えていることは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、つい見入ってしまったものは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、つい見入ってしまったものは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きな動物のしぐさを教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きな動物のしぐさを教えて。' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '町の中で好きな音は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '町の中で好きな音は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家の中で最近便利だと思ったものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家の中で最近便利だと思ったものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '大切なものを選ぶとき、何を基準にする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '大切なものを選ぶとき、何を基準にする？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'いつか誰かに贈りたい、手作りのものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'いつか誰かに贈りたい、手作りのものは？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、家族によく言われた言葉は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、家族によく言われた言葉は？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'お鍋に欠かせないと思う具は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'お鍋に欠かせないと思う具は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分を紹介するとき、家族には何を知っていてほしい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分を紹介するとき、家族には何を知っていてほしい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、できるようになったことや試したことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、できるようになったことや試したことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自然の中で聞いてみたい音は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自然の中で聞いてみたい音は？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'いつか乗ってみたい電車や路線は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'いつか乗ってみたい電車や路線は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '直しながら使っているものや、直してみたいものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '直しながら使っているものや、直してみたいものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '最近、自分らしいなと思った出来事は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '最近、自分らしいなと思った出来事は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'カレンダーの空いた日に、何を書き込みたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'カレンダーの空いた日に、何を書き込みたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔の写真を一枚思い浮かべるなら、どんな写真？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔の写真を一枚思い浮かべるなら、どんな写真？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族におすすめしたい食べものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族におすすめしたい食べものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族でひとつの記念日を増やすなら、何の日にする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族でひとつの記念日を増やすなら、何の日にする？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、会いたいなと思い浮かべた人は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、会いたいなと思い浮かべた人は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '季節の便りを送るなら、何の絵を添えたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '季節の便りを送るなら、何の絵を添えたい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '歩きながら見つけた面白いものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '歩きながら見つけた面白いものは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自由な時間が三十分できたら、何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自由な時間が三十分できたら、何をしたい？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '言葉にしなくても伝わったと感じたことはある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '言葉にしなくても伝わったと感じたことはある？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族との思い出を箱に入れるなら、何を入れたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族との思い出を箱に入れるなら、何を入れたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ苦手で、今は平気になったものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ苦手で、今は平気になったものは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころと今で、好みが変わった食べものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころと今で、好みが変わった食べものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族の写真につけたい、ひとことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族の写真につけたい、ひとことは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日の夕方は、どんなふうに過ごしたい？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日の夕方は、どんなふうに過ごしたい？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '桜の時期に思い出すことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '桜の時期に思い出すことは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '名前の由来が気になる町や場所はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '名前の由来が気になる町や場所はある？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かの作品で、すてきだと思ったものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かの作品で、すてきだと思ったものは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'これからも忘れずにいたい、うれしい瞬間は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'これからも忘れずにいたい、うれしい瞬間は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '庭に椅子を一つ置くなら、何を眺めたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '庭に椅子を一つ置くなら、何を眺めたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころに覚えて、今もできることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころに覚えて、今もできることは？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '食卓にあると気分が明るくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '食卓にあると気分が明るくなるものは？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に見せたい、自分のお気に入りは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に見せたい、自分のお気に入りは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、自分のペースでできたことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、自分のペースでできたことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '夏の夜に楽しみにしていたことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '夏の夜に楽しみにしていたことは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '宿でゆっくり過ごすなら、何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '宿でゆっくり過ごすなら、何をしたい？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分で名前をつけたものはある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分で名前をつけたものはある？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '何も予定がない日に、安心できる過ごし方は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '何も予定がない日に、安心できる過ごし方は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一日をゆっくりにできたら、どの時間を長くしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一日をゆっくりにできたら、どの時間を長くしたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '昔の遊びをひとつ家族に教えるなら、何を選ぶ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '昔の遊びをひとつ家族に教えるなら、何を選ぶ？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'おいしかった料理の名前をひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'おいしかった料理の名前をひとつ教えて。' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族と一緒に選びたいものはある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族と一緒に選びたいものはある？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、ありがとうを伝えるなら、誰に何を伝えたい？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、ありがとうを伝えるなら、誰に何を伝えたい？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '落ち葉を一枚選ぶなら、どんな色や形がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '落ち葉を一枚選ぶなら、どんな色や形がいい？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '旅先で知った、すてきな習慣はある？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '旅先で知った、すてきな習慣はある？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '落ち着く灯りは、どんな明るさや色？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '落ち着く灯りは、どんな明るさや色？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '気持ちが明るくなる色や景色は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '気持ちが明るくなる色や景色は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分のマークを作るなら、何を描いてみたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分のマークを作るなら、何を描いてみたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どものころ、どんな靴や服がお気に入りだった？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どものころ、どんな靴や服がお気に入りだった？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '好きなお寿司、またはごはん料理は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '好きなお寿司、またはごはん料理は？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族に似合いそうな花を思い浮かべるなら？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族に似合いそうな花を思い浮かべるなら？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日の一日に題名をつけるなら？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日の一日に題名をつけるなら？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '寒い日の、お気に入りの温まり方は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '寒い日の、お気に入りの温まり方は？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '引っ越しても覚えていたい景色は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '引っ越しても覚えていたい景色は？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '気分を変えたいとき、部屋で何を変える？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '気分を変えたいとき、部屋で何を変える？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分へ小さなごほうびを贈るなら、何にする？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分へ小さなごほうびを贈るなら、何にする？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族のカレンダーに加えたい楽しみは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族のカレンダーに加えたい楽しみは？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '子どもの自分に会えたら、何を話しかけたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '子どもの自分に会えたら、何を話しかけたい？' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'おやつを誰かと半分こするなら、何がいい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'おやつを誰かと半分こするなら、何がいい？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家族から教わりたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家族から教わりたいことは？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、明日も続けたいと思ったことは？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、明日も続けたいと思ったことは？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '晴れた日に干すと、うれしくなるものは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '晴れた日に干すと、うれしくなるものは？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '目的を決めずに散歩するなら、どんな道を選ぶ？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '目的を決めずに散歩するなら、どんな道を選ぶ？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '家に帰って、最初にしたくなることは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '家に帰って、最初にしたくなることは？' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '誰かに伝えてよかったと思う言葉は？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '誰かに伝えてよかったと思う言葉は？' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '来年の同じころ、何を楽しんでいたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '来年の同じころ、何を楽しんでいたい？' AND available_on IS NULL);

-- 子どものころ
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '育った町の好きなところをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '育った町の好きなところをひとつ教えて。' AND available_on IS NULL);

-- 食べもの
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '一日だけ小さなお店を開くなら、何を出したい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '一日だけ小さなお店を開くなら、何を出したい？' AND available_on IS NULL);

-- 家族との会話
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '次に家族と会ったら、最初に何をしたい？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '次に家族と会ったら、最初に何をしたい？' AND available_on IS NULL);

-- 今日の小さな発見
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '今日、自分に合っていた服装は？', NULL, 1, 1020, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '今日、自分に合っていた服装は？' AND available_on IS NULL);

-- 季節と自然
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '身近な自然に名前をつけるなら、何にどんな名前をつける？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '身近な自然に名前をつけるなら、何にどんな名前をつける？' AND available_on IS NULL);

-- 町と旅
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '次の小さなお出かけで楽しみにしたいことは？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '次の小さなお出かけで楽しみにしたいことは？' AND available_on IS NULL);

-- 好きなことと暮らし
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '自分だけの小さな楽しみを教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '自分だけの小さな楽しみを教えて。' AND available_on IS NULL);

-- 気持ちと思い出
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT 'この一年で、できるようになったことをひとつ教えて。', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = 'この一年で、できるようになったことをひとつ教えて。' AND available_on IS NULL);

-- 想像とこれから
INSERT INTO questions (prompt, available_on, is_active, publish_start_minute, publish_end_minute)
SELECT '次にこのアプリで家族へ届けたいのは、どんな話？', NULL, 1, 540, 1140
WHERE NOT EXISTS (SELECT 1 FROM questions WHERE prompt = '次にこのアプリで家族へ届けたいのは、どんな話？' AND available_on IS NULL);
