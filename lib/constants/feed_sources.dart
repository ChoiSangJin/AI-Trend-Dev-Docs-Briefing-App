import '../models/briefing.dart';

const defaultFeedSources = <FeedSource>[
  FeedSource(
    id: 'openai',
    name: 'OpenAI News',
    url: 'https://openai.com/news/rss.xml',
    category: '공식 업데이트',
  ),
  FeedSource(
    id: 'openai-sdk',
    name: 'OpenAI Python SDK',
    url: 'https://github.com/openai/openai-python/releases.atom',
    category: '공식 업데이트',
  ),
  FeedSource(
    id: 'anthropic-sdk',
    name: 'Anthropic Python SDK',
    url: 'https://github.com/anthropics/anthropic-sdk-python/releases.atom',
    category: '공식 업데이트',
  ),
  FeedSource(
    id: 'claude-code',
    name: 'Claude Code',
    url: 'https://github.com/anthropics/claude-code/releases.atom',
    category: '공식 업데이트',
  ),
  FeedSource(
    id: 'google-ai',
    name: 'Google AI Blog',
    url: 'https://blog.google/technology/ai/rss/',
    category: '공식 업데이트',
  ),
  FeedSource(
    id: 'huggingface',
    name: 'Hugging Face',
    url: 'https://huggingface.co/blog/feed.xml',
    category: '공식 업데이트',
  ),
  FeedSource(
    id: 'simon',
    name: 'Simon Willison',
    url: 'https://simonwillison.net/atom/everything/',
    category: '리서치 & 인사이트',
  ),
  FeedSource(
    id: 'papers',
    name: 'Daily Papers · RSSHub',
    url: 'https://rsshub.app/huggingface/daily-papers',
    fallbackUrl: 'https://export.arxiv.org/rss/cs.AI',
    category: '리서치 & 인사이트',
  ),
  FeedSource(
    id: 'techcrunch',
    name: 'TechCrunch AI',
    url: 'https://techcrunch.com/category/artificial-intelligence/feed/',
    category: '리서치 & 인사이트',
  ),
  FeedSource(
    id: 'geeknews',
    name: 'GeekNews',
    url: 'https://news.hada.io/rss/news',
    category: '리서치 & 인사이트',
  ),
];
