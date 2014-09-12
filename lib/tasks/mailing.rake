# encoding : UTF-8

namespace :mailing do

	desc "Création du fichier de mailing locale"
	task :generate_aliases => :environment do
		list = ""
		Adherent.not_archived.each do |a|
			list = list + a.email + ", "
		end

		File.open("#{Rails.root}/tmp/aliases_adherents",'w+') do |f|
			f.write(list)
		end
	end

	desc "Envoi du fichier sur le asgard"
	task :synchro_asgard => :environment do
		Net::SCP.start("10.5.0.8", "sapphire", :password => Passwords::Asgard) do |scp|
			scp.upload! "#{Rails.root}/tmp/aliases_adherents", "/etc/aliases_adherents"
		end
		Net::SSH.start('10.5.0.8', 'sapphire', :password => Passwords::Asgard) do |ssh|
			ssh.exec("sudo newaliases")
		end
	end

	desc "Synchroniser asgard et la BDD de Sapphire"
	task :synchronisation => :environment do
		Rake::Task["mailing:generate_aliases"].invoke
		Rake::Task["mailing:synchro_asgard"].invoke
	end
end
