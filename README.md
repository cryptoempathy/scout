# Scout

A government-wide search and notification system. Currently deployed to [scout.sunlightfoundation.com](https://scout.sunlightfoundation.com/).

[![Build Status](https://secure.travis-ci.org/sunlightlabs/scout.png)](http://travis-ci.org/sunlightlabs/scout)

## Setting Up

Scout is developed and tested on **Ruby 2.1.0**.

**Recommended**: use [rbenv](https://github.com/sstephenson/rbenv) to install Ruby 2.1.0 to your home directory.

You need a MongoDB server. Scout will create its own database and collections as needed.

After a `gem install bundler`, install included dependencies with:

```bash
bundle install --local
```

Create configuration files:

```bash
cp config.ru.example config.ru
cp config/config.yml.example config/config.yml
```

Change anything in `config.yml` that needs to be changed. Among other things, you will need to add your own Sunlight API key. You can get an API key [here](http://sunlightfoundation.com/api/accounts/register/). You can change the MongoDB configuration in this file if you need to.

Then run the app on port 8080 with:

```
bundle exec unicorn
```

## What It Does

* Alice visits the [Scout website](https://scout.sunlightfoundation.com/) and searches for terms of interest to her, e.g. ["intellectual property"](https://scout.sunlightfoundation.com/search/all/intellectual%20property).
* Alice subscribes to be sent messages via email when new items are published for those search terms: that is, new items related to her interest.
* Soon after new items are published, Alice receives one email message per interest, which may contain multiple new items.

### Notification settings

Alice may [log in](https://scout.sunlightfoundation.com/login) to [configure notification settings](https://scout.sunlightfoundation.com/account/settings):

* She may change the email frequency from "immediate" to "daily", or turn off all notifications. If daily, she receives a single email message for all interests once per day.
* She may [configure interests](https://scout.sunlightfoundation.com/account/subscriptions) to have different notification settings: she may set a notification to be sent immediately or daily, or she may turn off notifications for the interest.

### Collections

* Alice may [tag interests](https://scout.sunlightfoundation.com/account/subscriptions). All interests with the same tag are called a *collection* of interests.
* Collections are private by default, but if Alice fills in her user profile, she may share the collection in public.
* Bob may subscribe to Alice's collection to be sent messages when new items are published related to the interests in the collection. If Alice makes the collection private again, Bob will no longer receive messages.

### Other features

* Importing and delivering alerts for any RSS/Atom feed.
* All Scout-generated RSS feeds have [CORS](http://enable-cors.org/) enabled, so they can be accessed client-side directly, from any remote website.

## Under the Hood

* Scout checks for new items in multiple data sources. To add a new data source, you must write a *subscription adapter*. The adapter tells Scout how to query the data source with the search terms provided by its users.
* When users subscribe to be sent messages, they create an *interest*. The user may choose to receive new items for all data sources, or just one. An interest will have one or more *subscriptions* per data source.

## Re-use

We'd really love it if others used the Scout codebase to set up their own alert system. To that end, Scout's architecture is fairly well decoupled from the specific data sources that Sunlight's implementation currently uses.

But if you do want to set this up yourself, there will surely turn out to be more to do! Send [konklone](https://github.com/konklone) a message if this is something you're interested in.

### Custom Adapters

Set the environment variable `SCOUT_ADAPTER_PATH` to the path to the directory containing your adapters, for example:

```bash
SCOUT_ADAPTER_PATH=/path/to/adapters bundle exec unicorn
```

Each file within this directory must define an adapter class, and the filename must be the lowercase, underscored version of the class name. The adapter class must be defined in a `Subscriptions::Adapters` module.

### Maintaining Scout

It's helpful to understand a few things about keeping Scout running.

#### Upgrading Ruby

To upgrade the Ruby version, do the following in **each environment** Scout will run:

1. Update rbenv and ruby-build, by visiting `$HOME/.rbenv` and `$HOME/.rbenv/plugins/ruby-build` and running `git pull` in both.
2. Run `rbenv install [version]`, where `[version]` might be `2.1.1` or `2.2.0`.
3. Update `.ruby-version` in the project root, to reflect the version you installed, and commit this to the repository.
4. Activate the new Ruby version. (`rbenv global [version]` is one way to do this.)
5. Install bundler with `gem install bundler`.
6. Install dependencies with `bundle install --local`.

You should also run the test suite with `rake` to make sure everything is fine! But you probably only need to do that in one environment.

#### Entering the admin console

An app console can be opened using `irb`, which comes with Ruby. It is very similar to `ipython` for Python.

Any text in `$HOME/.irbrc` will be automatically run as `irb` on startup.

Our production server is configured with a `.irbrc` that will load the app environment **automatically**, when `irb` is run from the app's current working directory.

But if you want to do it yourself, it's:

```ruby
require 'rubygems'
require 'bundler/setup'
require './config/environment'
```

Once those have been executed, classes like `User` and `Delivery` will be available to you.

#### Manually unsubscribing users

Sometimes, users write in and want to be unsubscribed, and no matter what you tell them, they insist the process is broken or that you should do it.

So, given an email address for a user you wish to unsubscribe:

* Open up an `irb` console with the app environment loaded (see prior section).
* `user = User.where(email: "their.email@example.com").first`
* (Double check that it's the right user and email address.)
* `user.unsubscribe!`

This will log an `Event` in the database recording the time and email of the unsubscribe, and what that user's notification values were prior to the unsubscribe.

#### Admin emails

Various warnings or errors may be delivered to you as Scout runs. Here's what some of them may look like:

* `Postmark Exception | Bad email: [email address]` - This means we got a hard bounce or spam complaint from Postmark (from their attempt to send the email), and we should treat this user's email as unusable. Users are **automatically unsubscribed** from future emails when these events occur, so the email does not require any action.
* `New users for [YYYY-MM-DD]` - Each day, a report of new users from the previous day. One email is sent for Scout, one email is sent for Open States. For users who signed up via the "quick signup" method, their account may say "(unconfirmed)" next to it, if they didn't confirm their account by the time the email was sent.
* `Unsubscribe: [email]` - Any time a user manually chooses to unsubscribe, using the Unsubscribe From Everything workflow (linked at the bottom of each alert email), this email is sent to the admin. It requires no action, but you know, if a ton of them start happening, maybe perk up.
* `check:federal_bills_upcoming_floor | 30 errors while checking...` - This usually means there was an error from the remote API during a routine check. This example is taken from when Scout happened to be in the middle of checking for upcoming floor activity from the Congress API, and the Congress API was mid-deploy (which involves several seconds of downtime). Unless the number of errors is egregious, or the emails consistent, this is probably not actionable.
* `Check | XXX sets of backfills today, not delivered` - This means that during a routine check, Scout detected "backfills" -- results with an old date, but which the API had not previously seen before. These can occur for a variety of reasons, and most of our properties produce them now and then. Open States and the Congress API produce these most frequently, and it's not certain why. Unless the number of backfills is egregious, or the emails consistent, this is probably not actionable.

#### Deploying to the server

This project uses [fabric](#) for deployment, and its recipe is in [fabfile.py](fabfile.py).

To deploy the latest code to production:

```bash
fab deploy --set target=production
```

To restart the server:

```bash
fab restart
````

#### Disabling cronjobs

If things are going haywire, and you want to just stop Scout from checking for new things or possibly emailing people, run the fabric task:

```bash
fab disable_crontab
```

This just logs into the production server and runs `rake disable_crontab`.

To turn the crontab back on, use `fab set_crontab` or `rake set_crontab` as appropriate.

**Note**: Disabling the crontab will actually **replace** the crontab with an alternative "disabled" crontab, whose contents are at [config/cron/production/disabled](config/cron/production/disabled). This contains a single task that runs every 6 hours, warning the admin that the crontab has not yet been turned back on. This is a safety valve

#### Backups

Currently, backups are performed by a shell script on the MongoDB server that Scout uses. That script has been replicated in source control at [config/cron/production/backup.sh](config/cron/production/backup.sh).

The backup script exports many, but not all, of the collections in MongoDB to disk, tarballs them up, and stores them in S3.

The reasons for backing up, or not backing up, individual collections, are annotated in the comments in [the backup script](config/cron/production/backup.sh).

The tiny crontab that this user runs on the Scout MongoDB server is replicated at [config/cron/backup](config/cron/backup) (it references a `to-s3.sh` that is the same as the the backup script in this repo).

#### Backup Monitoring

A rake task, `rake backups:check`, runs once a day, a couple hours after the backup itself runs, that looks to make sure that a backup file has been uploaded to S3 for the previous day, and that it is not 0 bytes.

This is a safety valve, to try to catch when the backup script may have stopped working, for any reason. **It is not perfect**: other mechanisms should be employed, possibly including snapping EBSes.


### License

Copyright (c) 2011-2014 Sunlight Foundation, [released](https://github.com/sunlightlabs/scout/blob/master/LICENSE) under the [GNU General Public License, Version 3](http://www.gnu.org/licenses/gpl-3.0.txt).