# -*- encoding : utf-8 -*-
class Switch < ActiveRecord::Base

scope :not_archived, -> { where(archived: false)}

# Surveillance par la gem public_activity
	include PublicActivity::Common

# Bibliothèques netconf
	require 'pp'
	require 'net/netconf/jnpr'
	require 'junos-ez/stdlib'

# Attributs et associations	

	attr_accessible :community, :ip_admin, :description,
                    :ports_attributes
  attr_accessor :number_of_ports #Permet à l'utilisateur de rentrer le nombre de ports à créer pour le switch

	has_many :ports, dependent: :destroy, inverse_of: :switch

# Validations

	validates :community, presence: true
	validates :ip_admin, presence: true, uniqueness: true
  validates :description, presence: true

  accepts_nested_attributes_for :ports


  def occupied_ports_count
    number_of_occupied_ports = 0
    self.ports.each do |port|
      unless port.room == nil
        number_of_occupied_ports += 1
      end
    end
    number_of_occupied_ports
  end

	#Renvoie une interface SNMP pour manager le switch/wifiAp à distance
    def snmp_interface(options={})
      if @interface
        return @interface
      else
        #interfaceClass=(self.read_attribute(:model) + "_interface").camelize.constantize
        #@interface=interfaceClass.new(ip)
        #return @interface

        @interface = NetgearInterface.new(self.ip_admin, self.community)
      end
    end

    def connect_by_netconf
	login = { :target => self.ip_admin, :username => "root", :password => "abc123" }
	#Ouverture de session
	session = Netconf::SSH::new(login)

	if(session.open())
		#Chargement des fonctions nécessaires
		Junos::Ez::Provider(session) #Fonctionnalités de base : version firmware ...
		Junos::Ez::L1ports::Provider(session, :l1_ports) #Management des ports physiques
		Junos::Ez::L2ports::Provider(session, :l2_ports) #Management couche 2
		Junos::Ez::Vlans::Provider(session, :vlans) #Management des vlans
		Junos::Ez::Config::Utils(session, :cu) # Fonctions nécessaires au commit
	else
		puts "Erreur lors de la connection vers " + self.ip_admin.to_s
	end

	session
    end

    def disconnect_by_netconf(session)
	if(session)
		puts "Fermeture..."
		session.close
		puts "Fermé."
	end
    end

    def connected_by_netconf?(session)
	begin
		if(session.facts.read! != nil)
			true
		end
	rescue 
		false 
	end
    end

    def get_changes(switch_conf)
        config = Array.new

		#puts switch_conf
        
        self.ports.each do |p|
            if(p.managed)
                conf_port = Hash.new

                #Vlan
                if(switch_conf[p.number-1][:vlan_id] != p.get_authorized_vlan)
                    conf_port[:vlan_id] = p.get_authorized_vlan
                else
                    conf_port[:vlan_id] = nil
                end

                #Status admin des ports
                #A modifier lorsque le prerezotage sera disponible.
                if(p.room != nil && p.room.adherent != nil)
                    if(switch_conf[p.number-1][:admin_status] != p.room.adherent.actif?)
                        conf_port[:admin_status] = p.room.adherent.actif?
                    else
                        conf_port[:admin_status] = nil
                    end
                
                    conf_port[:allowed_macs] = Hash.new

                    #Gestion des allowed macs
                    if(p.room.adherent.rezoman != true)
						#Recuperation des macs à ajouter
    	                conf_port[:allowed_macs][:add] = Array.new
        	            p.room.adherent.computers.each do |computer|
            	            if(computer.archived == false)
                	            to_be_added = true
                    	        switch_conf[p.number-1][:allowed_macs].each do |switch_mac|
                        	        if(computer.mac_address == switch_mac)
                            	        to_be_added = false
                                	end
	                            end
    	                        if(to_be_added == true)
				            	    conf_port[:allowed_macs][:add] << computer.mac_address
            	                end
			    	        end
                    	end

	                    #Recuperation des mac à supprimer
    	                conf_port[:allowed_macs][:del] = Array.new
        	            switch_conf[p.number-1][:allowed_macs].each do |switch_mac|
            	            to_be_deleted = true
                	        p.room.adherent.computers.each do |computer|
                    	        if(computer.archived == false && computer.mac_address == switch_mac)
                        	        to_be_deleted = false
                            	end
	                        end
    	                    if(to_be_deleted == true)
        	                    conf_port[:allowed_macs][:del] << switch_mac
            	            end
                	    end

						#Nombre de macs
						conf_port[:allowed_macs][:number] = p.room.adherent.computers.length
					else
						#Recuperation des macs à ajouter
    	                conf_port[:allowed_macs][:add] = Array.new
        	            
	                    #Recuperation des mac à supprimer
    	                conf_port[:allowed_macs][:del] = Array.new
        	            switch_conf[p.number-1][:allowed_macs].each do |switch_mac|
        	                conf_port[:allowed_macs][:del] << switch_mac
                	    end

						#Nombre de macs indéfini pour rezoman
						conf_port[:allowed_macs][:number] = -1
					end

                    #Verification de la necessité de reconfigurer les macs
                    if(conf_port[:allowed_macs][:add].length == 0 && conf_port[:allowed_macs][:del].length == 0)
                        conf_port[:allowed_macs] = nil
                    end
                end
                if(conf_port[:vlan_id] == nil && conf_port[:admin_status] == nil && conf_port[:allowed_macs] == nil)
                    conf_port = nil
                end
                config << conf_port
            else
                config << nil
            end
        end

		#puts config

        config
    end

    def commit_modifs_by_netconf(session)
	if (session.cu.commit?)
		if (session.cu.commit!)
			puts "Commit réussi"
		else
			puts "Echec du commit"
		end
	else
		puts "Les données à commiter sont invalides"
	end
    end

end
