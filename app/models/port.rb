# -*- encoding : utf-8 -*-
class Port < ActiveRecord::Base
	default_scope order('number ASC')
# Surveillance par la gem public_activity
	include PublicActivity::Common

# Attributs et associations	

	attr_accessible :number, :switch_id, :room, :managed

	has_one :room, inverse_of: :port
	belongs_to :switch, inverse_of: :ports

# Validations

	validates :number, presence: true
	validates :switch, presence: true

	def designation
		switch.ip_admin + ":" + number.to_s
	end


	#charge l'état du port (enabled/disabled) et les vlans correspondants par SNMP
	#Ne fonctionne pas
	# def refresh_from_snmp

	# 	snmp_interface = self.switch.snmp_interface
	# 	vlans_nums = snmp_interface.vlans_ids

	# 	vlans_nums.each do |vlan_number|
	# 		if snmp_interface.is_on_vlan?(self.number,vlan_number) && self.vlan_connections.where(vlan: vlan_number).empty?
	# 			self.vlan_connections << new VlanConnection(vlan: Vlan.find_by_number(vlan_number))
	# 		end
	# 	end

	# 	self.vlan_connections.each do |vlan_connection|
	# 		vlan_number = vlan_connection.vlan
	# 		unless snmp_interface.is_on_vlan?(self.number,vlan_number)
	# 			vlan_connection.destroy
	# 			return
	# 		end
	# 		if vlans_nums.include? vlan_num 
	# 			connexion.tagged=snmp_interface.is_on_tagged_vlan?(self.number,vlan_number)
	# 			connexion.save
	# 		end
	# 	end
	# 	self.enabled=snmp_interface.enabled?(self.number)
	# 	save
	# end

	#Méthode qui met à jour les VLANs autorisés sur un port ainsi que la sécurité
	def update_vlans_by_snmp
		return nil unless managed
		#On Vérifie sur quel VLAN on doit mettre ce port
		if self.room.nil? or self.room.adherent.nil? or self.room.adherent.should_be_disconnected?
			new_vlan = {:vlan => VLAN::Prerezotage, :tagged => false}
			new_port_security = 2 #1 pour activer, 2 pour désactiver
		elsif self.room.adherent.supelec?
			new_vlan = {:vlan => VLAN::Supelec, :tagged => false}
			new_port_security = if self.room.adherent.rezoman then 2 else 1 end
		else
			new_vlan = {:vlan => VLAN::Exterieur, :tagged => false}
			new_port_security = 1
		end

		#On récupère l'interface SNMP
		intf = self.switch.snmp_interface

		#On supprime les VLANs non désirés sur ce port
		deleted_vlans = []
		old_vlans = intf.get_vlans(self.number)

		old_vlans.each do |vlan|
			if vlan != new_vlan[:vlan] or intf.is_on_tagged_vlan?(self.number, vlan) != new_vlan[:tagged]
				deleted_vlans << {:vlan => vlan, :tagged => intf.is_on_tagged_vlan?(self.number, vlan)}
				intf.del_vlan(self.number, vlan)
			end
		end

		changes = {:port => self.number, :added => [], :deleted => deleted_vlans}

		#On ajoute le bon VLAN si nécessaire
		if !new_vlan[:tagged] && !intf.is_on_untagged_vlan?(self.number, new_vlan[:vlan])
			intf.add_vlan_untagged(self.number, new_vlan[:vlan])
			changes[:added] << new_vlan
		end
		if new_vlan[:tagged] && !intf.is_on_tagged_vlan?(self.number, new_vlan[:vlan])
			intf.add_vlan_tagged(self.number, new_vlan[:vlan])
			changes[:added] << new_vlan
		end

		#On change l'état de PortSecurity si nécessaire
		if intf.get_port_security_status(self.number) != new_port_security
			intf.set_port_security_status(self.number, new_port_security)
			if new_port_security == 1
				changes[:port_security] = :enabled
			else
				changes[:port_security] = :disabled
			end
		end

		#On change le PVID
		intf.set_pvid(self.number, new_vlan[:vlan])

		#On nettoie les logs
		changes.delete(:added) if changes[:added].empty?
		changes.delete(:deleted) if changes[:deleted].empty?
		return true unless changes[:added] || changes[:deleted] || changes[:port_security]

		#On retourne un hash des modifications effectuées
		changes
	end

	#Méthode qui permet de mettre à jour les adresses macs autorisées sur un port
	def update_mac_addresses_by_snmp
		return nil unless managed
		#On vérifie les adresses MACs qui doivent être autorisées sur ce port
		new_macs = []
		unless self.room.nil? or self.room.adherent.nil? or self.room.adherent.should_be_disconnected?
			supelec = self.room.adherent.supelec?
			vlan = if supelec then VLAN::Supelec else VLAN::Exterieur end
			self.room.adherent.computers.not_archived.each do |computer|
				new_macs << {:mac => computer.mac_address, :vlan => vlan}
			end
		end

		#On récupère l'interface SNMP et les MACs présentes sur ce port
		intf = self.switch.snmp_interface
		old_macs = format_mac_addresses(intf.list_macs(self.number))

		#Apparement on peut faire des différences de tableaux de hashs
		macs_to_add = new_macs - old_macs
		macs_to_delete = old_macs - new_macs

		macs_to_add.each do |mac|
			intf.add_mac(self.number, mac[:vlan], mac[:mac])
		end

		macs_to_delete.each do |mac|
			intf.del_mac(self.number, mac[:vlan], mac[:mac])
		end

		changes = {:port => self.number, :added => macs_to_add, :deleted => macs_to_delete}

		#On nettoie les logs
		changes.delete(:added) if changes[:added].empty?
		changes.delete(:deleted) if changes[:deleted].empty?
		return true unless changes[:added] || changes[:deleted]

		#On retourne un hash des modifications effectuées
		changes
	end
	
	private

	#Le texte brut est de la forme "VLAN1 MAC1,VLAN1 MAC2"
	def format_mac_addresses(text)
		macs = []
		text.split(",").each do |part|
			tmp = part.split("\s")
			macs << {:mac => tmp[1], :vlan => tmp[0].to_i}
		end
		macs
	end
end
