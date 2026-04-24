class ApiConstants {
  // Radio Browser API
  static const radioBrowserBaseUrl = 'https://de1.api.radio-browser.info';

  // Alternative servers for fallback
  static const radioBrowserServers = [
    'https://de1.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
  ];

  // Radio Browser Endpoints
  static const stationsSearch = '/json/stations/search';
  static const stationsTopClick = '/json/stations/topclick';
  static const stationsTopVote = '/json/stations/topvote';
  static const stationsByCountry = '/json/stations/bycountry';
  static const stationsByTag = '/json/stations/bytag';
  static const countries = '/json/countries';
  static const tags = '/json/tags';
  static const stationClick = '/json/url'; // Register click on station

  // Last.fm API (scrobble / love / user info only — album art no longer
  // uses Last.fm after the iTunes → Deezer → MB+CAA migration).
  static const lastfmBaseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const lastfmAuthUrl = 'https://www.last.fm/api/auth/';

  // Album art provider chain — order matters.
  static const itunesBaseUrl = 'https://itunes.apple.com';
  static const deezerBaseUrl = 'https://api.deezer.com';
  static const musicbrainzBaseUrl = 'https://musicbrainz.org';
  static const coverArtArchiveBaseUrl = 'https://coverartarchive.org';

  // MusicBrainz requires a User-Agent identifying the app + a contact
  // method. Update the URL if the repo moves. MusicBrainz will throttle
  // (or block) generic User-Agent strings more aggressively.
  static const musicbrainzUserAgent =
      'JustRadio/1.0 ( https://github.com/thecodemonk/JustRadio )';

  // Default limits
  static const defaultSearchLimit = 50;
  static const defaultTopLimit = 100;
}
